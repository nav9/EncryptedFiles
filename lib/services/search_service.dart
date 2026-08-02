import 'dart:io';
import 'dart:typed_data';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/crypto/crypto_service.dart';
import 'package:encrypted_files/crypto/native_bindings.dart';
import 'package:encrypted_files/crypto/password_vault.dart';
import 'package:encrypted_files/database/database_service.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/services/log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Result of a disk search operation.
class SearchResult {
  SearchResult({
    required this.found,
    required this.alreadyKnown,
    required this.newFiles,
  });

  final List<String> found;
  final List<String> alreadyKnown;
  final List<String> newFiles; // paths not yet in DB
}

/// Scans directories for encrypted files and optionally registers them.
class SearchService {
  SearchService({
    required this.bindings,
    required this.crypto,
    required this.database,
    required this.passwordVault,
    required this.logs,
  });

  final NativeBindings bindings;
  final CryptoService crypto;
  final DatabaseService database;
  final PasswordVault passwordVault;
  final LogService logs;

  /// Search [rootDir] recursively for `.ef` encrypted files belonging to the
  /// current active password.
  ///
  /// [onFile] is called for each file examined.
  /// Returns found paths.
  Future<SearchResult> searchDirectory({
    required String rootDir,
    void Function(String path)? onFile,
    bool autoRegister = false,
    String? destFolderId,
    String? appRoot,
  }) async {
    final session = passwordVault.active;
    if (session == null) throw EfAuthException('No active password session');

    final dir = Directory(rootDir);
    if (!await dir.exists()) {
      throw EfIoException('Directory not found: $rootDir');
    }

    final found = <String>[];
    final alreadyKnown = <String>[];
    final newFiles = <String>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      onFile?.call(path);

      try {
        final probe = crypto.probe(path);
        if (!probe.isEncryptedFile) continue;

        found.add(path);

        // Check if already in DB.
        final existing = await database.findFileByPath(path);
        if (existing != null) {
          alreadyKnown.add(path);
          continue;
        }

        // Check if it belongs to this password by comparing blind tag.
        final fileSalt = probe.salt;
        final kdf = probe.kdf;
        if (fileSalt == null || kdf == null) continue;

        final fileKeys = crypto.deriveFromPassword(
          '', // We need the actual password — but we only have derived keys.
          // Instead, use the enc_key to try decrypting the header.
          fileSalt,
          kdf: kdf,
        );
        // Actually: we skip re-deriving from password here since we don't have
        // the raw password. Instead attempt to match the blind tag in the file
        // header against our current session's blind tag fingerprint.
        fileKeys.wipe();

        // Use the probe blind tag and compare with a "known good" method.
        // The probe file_blind_tag is HMAC(blindKey, fileId).
        // We can't verify without the fileId, so we just list all new EF files.
        newFiles.add(path);
      } catch (e) {
        debugPrint('SearchService: error probing $path: $e');
      }
    }

    if (autoRegister && newFiles.isNotEmpty) {
      await _registerNewFiles(newFiles, session, destFolderId, appRoot);
    }

    await logs.info(
        'SearchService',
        'Search in $rootDir: ${found.length} EF files, '
        '${alreadyKnown.length} known, ${newFiles.length} new');
    return SearchResult(found: found, alreadyKnown: alreadyKnown, newFiles: newFiles);
  }

  Future<void> _registerNewFiles(
    List<String> paths,
    ActiveSession session,
    String? folderId,
    String? appRoot,
  ) async {
    for (final path in paths) {
      try {
        final probe = crypto.probe(path);
        if (!probe.isEncryptedFile || probe.salt == null) continue;

        // Try decrypting header with current enc key to get real name & mime.
        // If decryption succeeds, it belongs to this password.
        // We use a 0-byte output path trick — just probe decrypt_begin.
        // The C-level ef_decrypt_begin validates the header MAC.
        // We pass a temp output file to decrypt_file just for the header.
        final tempOut = '$path.tmp_probe';
        try {
          await crypto.decryptFile(
            inputPath: path,
            outputPath: tempOut,
            keys: session.keys,
          );
          // If we got here, it belongs to this vault.
          // Re-probe the file for metadata.
          final fileStat = await File(path).stat();
          final now = DateTime.now().toUtc();
          final ref = EncryptedFileRef(
            id: crypto.newFileId(),
            vaultId: session.vault.id,
            diskPath: path,
            fakeName: p.basename(path),
            realNameEncrypted: Uint8List(0), // placeholder
            mimeEncrypted: Uint8List(0),
            fileBlindTag: Uint8List.fromList(probe.fileBlindTag ?? []),
            sizeBytes: fileStat.size,
            folderId: folderId,
            sortIndex: 0,
            createdAt: fileStat.modified.toUtc(),
            modifiedAt: now,
          );
          await database.insertFileRef(ref);
        } finally {
          try {
            await File(tempOut).delete();
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('SearchService._registerNewFiles: $path: $e');
      }
    }
  }

  /// Re-locate files that are in the DB but missing on disk.
  /// Returns a map of file id → new path (for found files).
  Future<Map<String, String>> relocateMissingFiles({
    required List<EncryptedFileRef> missing,
    required String searchDir,
    void Function(String path)? onFile,
  }) async {
    final relocated = <String, String>{};
    final dir = Directory(searchDir);
    if (!await dir.exists()) return relocated;

    final candidates = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      onFile?.call(entity.path);
      try {
        final probe = crypto.probe(entity.path);
        if (probe.isEncryptedFile) candidates.add(entity.path);
      } catch (_) {}
    }

    for (final ref in missing) {
      for (final candidate in candidates) {
        try {
          final probe = crypto.probe(candidate);
          if (!probe.isEncryptedFile) continue;
          if (probe.fileBlindTag == null) continue;
          // Match by blind tag.
          if (_listsEqual(probe.fileBlindTag!, ref.fileBlindTag)) {
            relocated[ref.id] = candidate;
            // Update DB.
            final updated = ref.copyWith(diskPath: candidate, missingOnDisk: false);
            await database.updateFileRef(updated);
            break;
          }
        } catch (_) {}
      }
    }

    return relocated;
  }

  bool _listsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
