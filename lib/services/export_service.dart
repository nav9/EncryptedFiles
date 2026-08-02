import 'dart:io';

import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/crypto/crypto_service.dart';
import 'package:encrypted_files/crypto/password_vault.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/services/log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Handles decrypting vault files back to plaintext on disk.
class ExportService {
  ExportService({
    required this.crypto,
    required this.passwordVault,
    required this.logs,
  });

  final CryptoService crypto;
  final PasswordVault passwordVault;
  final LogService logs;

  /// Decrypt [ref] and write to [destDir] using the real filename.
  /// Returns the path of the exported plaintext file.
  Future<String> exportFile({
    required EncryptedFileRef ref,
    required String destDir,
  }) async {
    final session = passwordVault.active;
    if (session == null) throw EfAuthException('No active password session');

    final sourceFile = File(ref.diskPath);
    if (!await sourceFile.exists()) {
      throw EfIoException('Encrypted file missing: ${ref.diskPath}');
    }

    final realName = ref.realName ?? ref.fakeName;
    final outputPath = p.join(destDir, realName);

    await Directory(destDir).create(recursive: true);

    try {
      await crypto.decryptFile(
        inputPath: ref.diskPath,
        outputPath: outputPath,
        keys: session.keys,
      );
    } catch (e, st) {
      debugPrint('ExportService.exportFile decrypt failed: $e\n$st');
      try {
        await File(outputPath).delete();
      } catch (_) {}
      throw EfCryptoException('Decryption failed for $realName', cause: e);
    }

    await logs.info('ExportService', 'Exported $realName → $outputPath');
    return outputPath;
  }

  /// Export multiple files to [destDir], returning a map of id → exported path.
  Future<Map<String, String>> exportFiles({
    required List<EncryptedFileRef> refs,
    required String destDir,
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <String, String>{};
    for (var i = 0; i < refs.length; i++) {
      try {
        final path = await exportFile(ref: refs[i], destDir: destDir);
        results[refs[i].id] = path;
      } catch (e) {
        await logs.error('ExportService', 'Failed to export ${refs[i].realName}: $e');
      }
      onProgress?.call(i + 1, refs.length);
    }
    return results;
  }
}
