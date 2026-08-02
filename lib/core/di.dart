import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/crypto/crypto_service.dart';
import 'package:encrypted_files/crypto/native_bindings.dart';
import 'package:encrypted_files/crypto/password_vault.dart';
import 'package:encrypted_files/crypto/secure_memory.dart';
import 'package:encrypted_files/database/database_service.dart';
import 'package:encrypted_files/services/capture_service.dart';
import 'package:encrypted_files/services/download_service.dart';
import 'package:encrypted_files/services/export_service.dart';
import 'package:encrypted_files/services/import_service.dart';
import 'package:encrypted_files/services/log_service.dart';
import 'package:encrypted_files/services/media_service.dart';
import 'package:encrypted_files/services/permission_service.dart';
import 'package:encrypted_files/services/search_service.dart';
import 'package:encrypted_files/services/settings_service.dart';
import 'package:encrypted_files/streaming/stream_server_service.dart';
import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Lightweight service locator / dependency injection.
class AppDi {
  AppDi._();

  static late final String appRoot;
  static late final NativeBindings bindings;
  static late final CryptoService crypto;
  static late final DatabaseService database;
  static late final LogService logs;
  static late final SettingsService settings;
  static late final PasswordVault passwordVault;
  static late final StreamServerService streamServer;
  static late final ImportService importService;
  static late final ExportService exportService;
  static late final SearchService searchService;
  static late final DownloadService downloadService;
  static late final CaptureService captureService;
  static late final MediaService mediaService;
  static late final PermissionService permissions;
  static late final AppState appState;
  static late final SecureMemory secureMemory;

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) {
      return;
    }
    try {
      final support = await getApplicationSupportDirectory();
      appRoot = p.join(support.path, AppConstants.appFolderName);
      await Directory(appRoot).create(recursive: true);

      bindings = NativeBindings();
      bindings.load();
      secureMemory = SecureMemory();
      crypto = CryptoService(bindings);
      database = DatabaseService(appRoot);
      await database.open();
      logs = LogService(database);
      settings = SettingsService(database);
      await settings.load();
      passwordVault = PasswordVault(crypto, database, secureMemory);
      streamServer = StreamServerService(bindings, settings);
      permissions = PermissionService();
      importService = ImportService(
        crypto: crypto,
        database: database,
        passwordVault: passwordVault,
        settings: settings,
        logs: logs,
      );
      exportService = ExportService(
        crypto: crypto,
        passwordVault: passwordVault,
        logs: logs,
      );
      searchService = SearchService(
        bindings: bindings,
        crypto: crypto,
        database: database,
        passwordVault: passwordVault,
        logs: logs,
      );
      downloadService = DownloadService(
        crypto: crypto,
        database: database,
        passwordVault: passwordVault,
        settings: settings,
        logs: logs,
      );
      captureService = CaptureService(
        crypto: crypto,
        database: database,
        passwordVault: passwordVault,
        settings: settings,
        logs: logs,
      );
      mediaService = MediaService(streamServer: streamServer, logs: logs);
      appState = AppState(
        passwordVault: passwordVault,
        database: database,
        logs: logs,
        settings: settings,
        streamServer: streamServer,
      );

      await logs.info('AppDi', 'Initialized app root at $appRoot');
      _initialized = true;
    } catch (e, st) {
      debugPrint('AppDi.init failed: $e\n$st');
      rethrow;
    }
  }
}
