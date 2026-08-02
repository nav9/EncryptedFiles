import 'dart:io';
import 'dart:typed_data';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/crypto/crypto_service.dart';
import 'package:encrypted_files/crypto/password_vault.dart';
import 'package:encrypted_files/database/database_service.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/services/log_service.dart';
import 'package:encrypted_files/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Handles importing unencrypted files from disk into the encrypted vault.
class ImportService {
  ImportService({
    required this.crypto,
    required this.database,
    required this.passwordVault,
    required this.settings,
    required this.logs,
  });

  final CryptoService crypto;
  final DatabaseService database;
  final PasswordVault passwordVault;
  final SettingsService settings;
  final LogService logs;
  final _uuid = const Uuid();

  /// Encrypt [sourcePath] and store the encrypted file at [destDir].
  /// [fakeName] is the obfuscated on-disk name (if null, a UUID name is used).
  /// [folderId] optionally assigns the file to a virtual folder.
  ///
  /// Returns the new [EncryptedFileRef].
  Future<EncryptedFileRef> importFile({
    required String sourcePath,
    required String destDir,
    String? fakeName,
    String? folderId,
  }) async {
    final session = passwordVault.active;
    if (session == null) {
      throw EfAuthException('No active password session');
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw EfIoException('Source file not found: $sourcePath');
    }

    final realName = p.basename(sourcePath);
    final mimeType = lookupMimeType(sourcePath) ?? 'application/octet-stream';
    final sizeBytes = await sourceFile.length();

    // Build a unique file ID and blind tag.
    final fileId = _uuid.v4();
    final fileIdBytes = _uuidToBytes(fileId);
    final blindTag = crypto.fileBlindTag(session.keys, fileId: fileIdBytes);

    // Determine encrypted output path.
    final ext = _randomFakeExt();
    final storedFakeName = fakeName ?? '${_uuid.v4()}$ext';
    final outputPath = p.join(destDir, storedFakeName);

    await Directory(destDir).create(recursive: true);

    try {
      await crypto.encryptFile(
        inputPath: sourcePath,
        outputPath: outputPath,
        keys: session.keys,
        realName: realName,
        mimeType: mimeType,
        fileBlindTag: blindTag,
        chunkSize: settings.chunkBytes,
      );
    } catch (e, st) {
      debugPrint('ImportService.importFile encrypt failed: $e\n$st');
      try {
        await File(outputPath).delete();
      } catch (_) {}
      throw EfCryptoException('Encryption failed for $realName', cause: e);
    }

    // Encrypt metadata for storage.
    final realNameEnc = passwordVault.encryptMetadata(realName);
    final mimeEnc = passwordVault.encryptMetadata(mimeType);

    final now = DateTime.now().toUtc();
    final ref = EncryptedFileRef(
      id: fileId,
      vaultId: session.vault.id,
      diskPath: outputPath,
      fakeName: storedFakeName,
      realNameEncrypted: Uint8List.fromList(realNameEnc),
      mimeEncrypted: Uint8List.fromList(mimeEnc),
      fileBlindTag: Uint8List.fromList(blindTag),
      sizeBytes: sizeBytes,
      folderId: folderId,
      sortIndex: 0,
      createdAt: now,
      modifiedAt: now,
      realName: realName,
      mimeType: mimeType,
    );

    await database.insertFileRef(ref);
    await logs.info('ImportService', 'Imported $realName → $storedFakeName');
    return ref;
  }

  /// Encrypt a raw byte stream (e.g., from camera capture) into a new file.
  Future<EncryptedFileRef> importStream({
    required Stream<List<int>> source,
    required int plaintextSize,
    required String realName,
    required String mimeType,
    required String destDir,
    String? fakeName,
    String? folderId,
  }) async {
    final session = passwordVault.active;
    if (session == null) throw EfAuthException('No active password session');

    final fileId = _uuid.v4();
    final fileIdBytes = _uuidToBytes(fileId);
    final blindTag = crypto.fileBlindTag(session.keys, fileId: fileIdBytes);

    final ext = _extForMime(mimeType);
    final storedFakeName = fakeName ?? '${_uuid.v4()}$ext';
    final outputPath = p.join(destDir, storedFakeName);
    await Directory(destDir).create(recursive: true);

    try {
      await crypto.encryptStream(
        outputPath: outputPath,
        keys: session.keys,
        realName: realName,
        mimeType: mimeType,
        fileBlindTag: blindTag,
        chunkSize: settings.chunkBytes,
        plaintextSize: plaintextSize,
        source: source,
      );
    } catch (e, st) {
      debugPrint('ImportService.importStream encrypt failed: $e\n$st');
      try {
        await File(outputPath).delete();
      } catch (_) {}
      throw EfCryptoException('Stream encryption failed for $realName', cause: e);
    }

    final realNameEnc = Uint8List.fromList(passwordVault.encryptMetadata(realName));
    final mimeEnc = Uint8List.fromList(passwordVault.encryptMetadata(mimeType));
    final now = DateTime.now().toUtc();

    final ref = EncryptedFileRef(
      id: fileId,
      vaultId: session.vault.id,
      diskPath: outputPath,
      fakeName: storedFakeName,
      realNameEncrypted: realNameEnc,
      mimeEncrypted: mimeEnc,
      fileBlindTag: Uint8List.fromList(blindTag),
      sizeBytes: plaintextSize,
      folderId: folderId,
      sortIndex: 0,
      createdAt: now,
      modifiedAt: now,
      realName: realName,
      mimeType: mimeType,
    );

    await database.insertFileRef(ref);
    await logs.info('ImportService', 'Captured stream $realName → $storedFakeName');
    return ref;
  }

  Uint8List _uuidToBytes(String uuid) {
    final hex = uuid.replaceAll('-', '');
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  String _randomFakeExt() {
    const exts = ['.jpg', '.png', '.dat', '.bin', '.bak', '.tmp'];
    final idx = DateTime.now().microsecond % exts.length;
    return exts[idx];
  }

  String _extForMime(String mime) {
    if (mime.startsWith('image/')) return '.jpg';
    if (mime.startsWith('video/')) return '.mp4';
    if (mime.startsWith('audio/')) return '.m4a';
    return '.bin';
  }
}
