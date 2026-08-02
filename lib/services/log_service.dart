import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/database/database_service.dart';
import 'package:encrypted_files/database/models/log_entry.dart';
import 'package:flutter/foundation.dart';

class LogService {
  LogService(this._db);

  final DatabaseService _db;

  Future<void> log(LogLevel level, String tag, String message) async {
    try {
      await _db.insertLog(LogEntry(
        id: null,
        level: level,
        tag: tag,
        message: message,
        createdAt: DateTime.now().toUtc(),
      ));
      if (kDebugMode) {
        debugPrint('[${level.name.toUpperCase()}] $tag: $message');
      }
    } catch (e) {
      debugPrint('LogService failed: $e');
    }
  }

  Future<void> debug(String tag, String message) =>
      log(LogLevel.debug, tag, message);
  Future<void> info(String tag, String message) =>
      log(LogLevel.info, tag, message);
  Future<void> warning(String tag, String message) =>
      log(LogLevel.warning, tag, message);
  Future<void> error(String tag, String message) =>
      log(LogLevel.error, tag, message);

  Future<List<LogEntry>> recent({int limit = 200}) => _db.listLogs(limit: limit);
  Future<void> clear() => _db.clearLogs();
}
