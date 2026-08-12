import 'dart:io';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/database/models/log_entry.dart';
import 'package:encrypted_files/database/models/vault_model.dart';
import 'package:encrypted_files/database/models/virtual_folder.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  DatabaseService(this.appRoot);

  final String appRoot;
  Database? _db;

  Database get db {
    final d = _db;
    if (d == null) {
      throw EfIoException('Database not open');
    }
    return d;
  }

  Future<void> open() async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      final dbPath = p.join(appRoot, AppConstants.databaseFileName);
      _db = await openDatabase(
        dbPath,
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE password_vaults (
              id TEXT PRIMARY KEY,
              salt BLOB NOT NULL,
              blind_index BLOB NOT NULL UNIQUE,
              kdf_mem INTEGER NOT NULL,
              kdf_passes INTEGER NOT NULL,
              kdf_lanes INTEGER NOT NULL,
              created_at TEXT NOT NULL,
              is_decoy INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE virtual_folders (
              id TEXT PRIMARY KEY,
              vault_id TEXT NOT NULL,
              name_enc BLOB NOT NULL,
              parent_id TEXT,
              sort_index INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              modified_at TEXT NOT NULL,
              FOREIGN KEY(vault_id) REFERENCES password_vaults(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE file_refs (
              id TEXT PRIMARY KEY,
              vault_id TEXT NOT NULL,
              disk_path TEXT NOT NULL,
              fake_name TEXT NOT NULL,
              real_name_enc BLOB NOT NULL,
              mime_enc BLOB NOT NULL,
              file_blind_tag BLOB NOT NULL,
              size_bytes INTEGER NOT NULL DEFAULT 0,
              folder_id TEXT,
              sort_index INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              modified_at TEXT NOT NULL,
              FOREIGN KEY(vault_id) REFERENCES password_vaults(id) ON DELETE CASCADE
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_file_refs_vault ON file_refs(vault_id)',
          );
          await db.execute(
            'CREATE INDEX idx_file_refs_folder ON file_refs(folder_id)',
          );
          await db.execute(
            'CREATE INDEX idx_file_refs_path ON file_refs(disk_path)',
          );
          await db.execute('''
            CREATE TABLE app_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              level TEXT NOT NULL,
              tag TEXT NOT NULL,
              message TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE password_vaults ADD COLUMN is_decoy INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE virtual_folders ADD COLUMN modified_at TEXT',
            );
            await db.execute(
              'UPDATE virtual_folders SET modified_at = created_at WHERE modified_at IS NULL',
            );
          }
        },
      );
    } catch (e, st) {
      debugPrint('Database open failed: $e\n$st');
      throw EfIoException('Failed to open database', cause: e);
    }
  }

  Future<void> insertVault(VaultModel vault) async {
    await db.insert('password_vaults', vault.toMap());
  }

  Future<List<VaultModel>> listVaults() async {
    final rows = await db.query('password_vaults', orderBy: 'created_at ASC');
    return rows.map(VaultModel.fromMap).toList();
  }

  Future<VaultModel?> findVaultByBlindIndex(List<int> blindIndex) async {
    final rows = await db.query(
      'password_vaults',
      where: 'blind_index = ?',
      whereArgs: [blindIndex],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return VaultModel.fromMap(rows.first);
  }

  Future<void> insertFileRef(EncryptedFileRef ref) async {
    await db.insert('file_refs', ref.toMap());
  }

  Future<void> updateFileRef(EncryptedFileRef ref) async {
    await db.update(
      'file_refs',
      ref.toMap(),
      where: 'id = ?',
      whereArgs: [ref.id],
    );
  }

  Future<void> deleteFileRef(String id) async {
    await db.delete('file_refs', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<EncryptedFileRef>> listFileRefsForVault(String vaultId) async {
    final rows = await db.query(
      'file_refs',
      where: 'vault_id = ?',
      whereArgs: [vaultId],
      orderBy: 'sort_index ASC, created_at ASC',
    );
    return rows.map(EncryptedFileRef.fromMap).toList();
  }

  Future<EncryptedFileRef?> findFileByPath(String path) async {
    final rows = await db.query(
      'file_refs',
      where: 'disk_path = ?',
      whereArgs: [path],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return EncryptedFileRef.fromMap(rows.first);
  }

  Future<List<EncryptedFileRef>> listAllFileRefs() async {
    final rows = await db.query('file_refs');
    return rows.map(EncryptedFileRef.fromMap).toList();
  }

  Future<void> insertFolder(VirtualFolder folder) async {
    await db.insert('virtual_folders', folder.toMap());
  }

  Future<void> updateFolder(VirtualFolder folder) async {
    await db.update(
      'virtual_folders',
      folder.toMap(),
      where: 'id = ?',
      whereArgs: [folder.id],
    );
  }

  Future<void> deleteFolder(String id) async {
    await db.delete('virtual_folders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<VirtualFolder>> listFoldersForVault(String vaultId) async {
    final rows = await db.query(
      'virtual_folders',
      where: 'vault_id = ?',
      whereArgs: [vaultId],
      orderBy: 'sort_index ASC, created_at ASC',
    );
    return rows.map(VirtualFolder.fromMap).toList();
  }

  Future<int> countFilesInFolder(String folderId) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM file_refs WHERE folder_id = ?',
      [folderId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> insertLog(LogEntry entry) async {
    await db.insert('app_logs', entry.toMap());
    // FIFO rotation
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) AS c FROM app_logs'),
        ) ??
        0;
    if (count > AppConstants.maxLogEntries) {
      final overflow = count - AppConstants.maxLogEntries;
      await db.delete(
        'app_logs',
        where:
            'id IN (SELECT id FROM app_logs ORDER BY id ASC LIMIT ?)',
        whereArgs: [overflow],
      );
    }
  }

  Future<List<LogEntry>> listLogs({int limit = 200}) async {
    final rows = await db.query(
      'app_logs',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  Future<void> clearLogs() async {
    await db.delete('app_logs');
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
