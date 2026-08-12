import 'dart:io';

import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/crypto/crypto_service.dart';
import 'package:encrypted_files/crypto/password_vault.dart';
import 'package:encrypted_files/database/database_service.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/services/log_service.dart';
import 'package:encrypted_files/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Streams a URL download directly to disk as an encrypted file.
class DownloadService {
  DownloadService({
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

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// Download [url] and encrypt it directly to [destDir].
  /// [onProgress] receives (receivedBytes, totalBytes) — totalBytes may be -1.
  Future<EncryptedFileRef> downloadAndEncrypt({
    required String url,
    required String destDir,
    String? fakeName,
    String? folderId,
    void Function(int received, int total)? onProgress,
  }) async {
    final session = passwordVault.active;
    if (session == null) throw EfAuthException('No active password session');

    _cancelled = false;

    final uri = Uri.parse(url);
    final realName = p.basename(uri.path).isNotEmpty
        ? p.basename(uri.path)
        : 'download_${DateTime.now().millisecondsSinceEpoch}';
    final mimeType = lookupMimeType(realName) ?? 'application/octet-stream';

    final fileId = _uuid.v4();
    final fileIdBytes = _uuidToBytes(fileId);
    final blindTag = crypto.fileBlindTag(session.keys, fileId: fileIdBytes);

    final ext = p.extension(realName).isNotEmpty ? p.extension(realName) : '.bin';
    final storedFakeName = fakeName ?? '${_uuid.v4()}$ext';
    final outputPath = p.join(destDir, storedFakeName);

    await Directory(destDir).create(recursive: true);

    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', uri);
        final response = await client.send(request);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw EfIoException('HTTP ${response.statusCode} for $url');
        }

        final total = response.contentLength ?? -1;
        int received = 0;

        // We need total size for ef_encrypt_begin — stream size may be unknown.
        // Strategy: if Content-Length is known, stream directly.
        // Otherwise collect into a temp buffer (capped at available memory).
        final chunkSize = settings.chunkBytes;

        if (total > 0) {
          // Known size: stream directly.
          Stream<List<int>> source() async* {
            await for (final chunk in response.stream) {
              if (_cancelled) break;
              received += chunk.length;
              onProgress?.call(received, total);
              yield chunk;
            }
          }

          await crypto.encryptStream(
            outputPath: outputPath,
            keys: session.keys,
            realName: realName,
            mimeType: mimeType,
            fileBlindTag: blindTag,
            chunkSize: chunkSize,
            plaintextSize: total,
            source: source(),
          );

          if (_cancelled) {
            throw EfIoException('Download cancelled');
          }
        } else {
          // Unknown size: accumulate chunks, then encrypt.
          final bytes = <int>[];
          await for (final chunk in response.stream) {
            if (_cancelled) break;
            bytes.addAll(chunk);
            received += chunk.length;
            onProgress?.call(received, -1);
          }

          if (_cancelled) {
            throw EfIoException('Download cancelled');
          }

          final data = Uint8List.fromList(bytes);
          await crypto.encryptStream(
            outputPath: outputPath,
            keys: session.keys,
            realName: realName,
            mimeType: mimeType,
            fileBlindTag: blindTag,
            chunkSize: chunkSize,
            plaintextSize: data.length,
            source: Stream.value(data),
          );
        }
      } finally {
        client.close();
      }
    } catch (e, st) {
      debugPrint('DownloadService.downloadAndEncrypt failed: $e\n$st');
      try {
        await File(outputPath).delete();
      } catch (_) {}
      if (e is EfException) rethrow;
      throw EfIoException('Download failed: $url', cause: e);
    }

    final stat = await File(outputPath).stat();
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
      sizeBytes: stat.size,
      folderId: folderId,
      sortIndex: 0,
      createdAt: now,
      modifiedAt: now,
      realName: realName,
      mimeType: mimeType,
    );

    await database.insertFileRef(ref);
    await logs.info('DownloadService', 'Downloaded & encrypted $realName');
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
}
