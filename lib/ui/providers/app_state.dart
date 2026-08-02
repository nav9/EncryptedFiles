import 'dart:io';
import 'dart:typed_data';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/crypto/password_vault.dart';
import 'package:encrypted_files/database/database_service.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/database/models/virtual_folder.dart';
import 'package:encrypted_files/services/log_service.dart';
import 'package:encrypted_files/services/settings_service.dart';
import 'package:encrypted_files/streaming/stream_server_service.dart';
import 'package:flutter/foundation.dart';

/// Global application state managed via ChangeNotifier (Provider).
class AppState extends ChangeNotifier {
  AppState({
    required this.passwordVault,
    required this.database,
    required this.logs,
    required this.settings,
    required this.streamServer,
  });

  final PasswordVault passwordVault;
  final DatabaseService database;
  final LogService logs;
  final SettingsService settings;
  final StreamServerService streamServer;

  List<EncryptedFileRef> _fileRefs = [];
  List<VirtualFolder> _folders = [];
  bool _isLoading = false;
  String? _statusMessage;

  List<EncryptedFileRef> get fileRefs => List.unmodifiable(_fileRefs);
  List<VirtualFolder> get folders => List.unmodifiable(_folders);
  bool get isLoading => _isLoading;
  String? get statusMessage => _statusMessage;
  bool get hasSession => passwordVault.hasActivePassword;

  /// Returns file refs that belong to the given [folderId] (null = root).
  List<EncryptedFileRef> filesInFolder(String? folderId) =>
      _fileRefs.where((f) => f.folderId == folderId).toList();

  /// Returns sub-folders of [parentId] (null = root folders).
  List<VirtualFolder> subFolders(String? parentId) =>
      _folders.where((f) => f.parentId == parentId).toList();

  /// Load and decrypt metadata for all files/folders belonging to the
  /// current active session.
  Future<void> loadVaultContents() async {
    final session = passwordVault.active;
    if (session == null) {
      _fileRefs = [];
      _folders = [];
      notifyListeners();
      return;
    }

    _setLoading(true);
    try {
      final rawRefs = await database.listFileRefsForVault(session.vault.id);
      final rawFolders = await database.listFoldersForVault(session.vault.id);

      // Decrypt metadata for each file ref.
      final decryptedRefs = <EncryptedFileRef>[];
      for (final ref in rawRefs) {
        try {
          final realName = passwordVault.decryptMetadata(ref.realNameEncrypted);
          final mimeType = passwordVault.decryptMetadata(ref.mimeEncrypted);
          final exists = File(ref.diskPath).existsSync();
          decryptedRefs.add(ref.copyWith(
            realName: realName,
            mimeType: mimeType,
            missingOnDisk: !exists,
          ));
        } catch (e) {
          debugPrint('AppState: failed to decrypt metadata for ${ref.id}: $e');
          decryptedRefs.add(ref.copyWith(missingOnDisk: !File(ref.diskPath).existsSync()));
        }
      }

      // Decrypt folder names.
      final decryptedFolders = <VirtualFolder>[];
      for (final folder in rawFolders) {
        try {
          final name = passwordVault.decryptMetadata(
            Uint8List.fromList(folder.nameEncrypted),
          );
          final count = decryptedRefs
              .where((f) => f.folderId == folder.id)
              .length;
          decryptedFolders.add(folder.copyWith(name: name, fileCount: count));
        } catch (e) {
          debugPrint('AppState: failed to decrypt folder name ${folder.id}: $e');
          decryptedFolders.add(folder);
        }
      }

      _fileRefs = decryptedRefs;
      _folders = decryptedFolders;

      await logs.debug('AppState', 'Loaded ${_fileRefs.length} files, ${_folders.length} folders');
    } catch (e, st) {
      debugPrint('AppState.loadVaultContents failed: $e\n$st');
      await logs.error('AppState', 'Failed to load vault contents: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Clear all in-memory state (called on password clear).
  Future<void> clearSession() async {
    streamServer.clearKeys();
    await passwordVault.clearActive();
    _fileRefs = [];
    _folders = [];
    _statusMessage = null;
    notifyListeners();
    await logs.info('AppState', 'Session cleared, all keys wiped from RAM');
  }

  /// Apply sorting to currently loaded file refs within the optional [folderId].
  void sortFiles(SortMode mode, {String? folderId}) {
    List<EncryptedFileRef> target;
    List<EncryptedFileRef> others;

    if (folderId != null) {
      target = _fileRefs.where((f) => f.folderId == folderId).toList();
      others = _fileRefs.where((f) => f.folderId != folderId).toList();
    } else {
      target = List.of(_fileRefs);
      others = [];
    }

    switch (mode) {
      case SortMode.nameAsc:
        target.sort((a, b) => (a.realName ?? a.fakeName).toLowerCase().compareTo(
            (b.realName ?? b.fakeName).toLowerCase()));
      case SortMode.nameDesc:
        target.sort((a, b) => (b.realName ?? b.fakeName).toLowerCase().compareTo(
            (a.realName ?? a.fakeName).toLowerCase()));
      case SortMode.createdAsc:
        target.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case SortMode.createdDesc:
        target.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SortMode.modifiedAsc:
        target.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
      case SortMode.modifiedDesc:
        target.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      case SortMode.manual:
        target.sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    }

    if (folderId != null) {
      _fileRefs = [...others, ...target];
    } else {
      _fileRefs = target;
    }
    notifyListeners();
  }

  /// Update a file ref in memory after a DB change.
  void updateRef(EncryptedFileRef updated) {
    final idx = _fileRefs.indexWhere((f) => f.id == updated.id);
    if (idx >= 0) {
      _fileRefs[idx] = updated;
      notifyListeners();
    }
  }

  /// Remove a file ref from memory after deletion.
  void removeRef(String id) {
    _fileRefs.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  /// Add a newly imported file to memory.
  void addRef(EncryptedFileRef ref) {
    _fileRefs.add(ref);
    notifyListeners();
  }

  void addFolder(VirtualFolder folder) {
    _folders.add(folder);
    notifyListeners();
  }

  void removeFolder(String id) {
    _folders.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  void setStatus(String? message) {
    _statusMessage = message;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  // Theme toggle helper.
  bool get isDarkTheme => settings.isDarkTheme;
  Future<void> setDarkTheme(bool value) async {
    await settings.setDarkTheme(value);
    notifyListeners();
  }
}
