import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/services/log_service.dart';
import 'package:encrypted_files/streaming/stream_server_service.dart';

/// High-level service for opening media in the localhost streaming server.
class MediaService {
  MediaService({required this.streamServer, required this.logs});

  final StreamServerService streamServer;
  final LogService logs;

  final Map<String, String> _activeTokens = {}; // fileId → token

  /// Register [ref] with the stream server and return its localhost URL.
  Future<String> getStreamUrl(EncryptedFileRef ref) async {
    // Return existing URL if already registered.
    if (_activeTokens.containsKey(ref.id)) {
      final url = streamServer.tokenToUrl(_activeTokens[ref.id]!);
      if (url != null) return url;
    }

    final result = await streamServer.register(ref.diskPath);
    _activeTokens[ref.id] = result.token;
    await logs.debug('MediaService', 'Registered ${ref.realName} → ${result.url}');
    return result.url;
  }

  /// Unregister a file from the stream server.
  Future<void> releaseUrl(EncryptedFileRef ref) async {
    final token = _activeTokens.remove(ref.id);
    if (token != null) {
      streamServer.unregister(token);
    }
  }

  /// Release all registered URLs (e.g., on password clear).
  Future<void> releaseAll() async {
    for (final token in _activeTokens.values) {
      streamServer.unregister(token);
    }
    _activeTokens.clear();
    await logs.debug('MediaService', 'All stream URLs released');
  }
}
