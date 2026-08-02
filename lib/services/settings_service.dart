import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/database/database_service.dart';

/// Persists app configuration into the SQLite settings table.
class SettingsService {
  SettingsService(this._db);

  final DatabaseService _db;

  bool isDarkTheme = true;
  int chunkBytes = AppConstants.defaultChunkBytes;
  bool autoSuggestChunk = true;

  // Streaming server chunk size override (0 = use file header)
  int streamChunkOverride = 0;

  Future<void> load() async {
    try {
      final theme = await _db.getSetting('darkTheme');
      if (theme != null) isDarkTheme = theme == '1';

      final chunk = await _db.getSetting('chunkBytes');
      if (chunk != null) chunkBytes = int.tryParse(chunk) ?? AppConstants.defaultChunkBytes;

      final autoChunk = await _db.getSetting('autoSuggestChunk');
      if (autoChunk != null) autoSuggestChunk = autoChunk == '1';

      final streamChunk = await _db.getSetting('streamChunkOverride');
      if (streamChunk != null) streamChunkOverride = int.tryParse(streamChunk) ?? 0;
    } catch (_) {
      // Use defaults on first launch.
    }
  }

  Future<void> setDarkTheme(bool value) async {
    isDarkTheme = value;
    await _db.setSetting('darkTheme', value ? '1' : '0');
  }

  Future<void> setChunkBytes(int value) async {
    chunkBytes = value;
    await _db.setSetting('chunkBytes', value.toString());
  }

  Future<void> setAutoSuggestChunk(bool value) async {
    autoSuggestChunk = value;
    await _db.setSetting('autoSuggestChunk', value ? '1' : '0');
  }

  Future<void> setStreamChunkOverride(int value) async {
    streamChunkOverride = value;
    await _db.setSetting('streamChunkOverride', value.toString());
  }
}
