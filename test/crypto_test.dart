/// Dart-native pure-Dart unit tests for the cryptographic layer.
///
/// These tests do NOT require the native shared library — they exercise
/// only the pure-Dart logic: blind index constants, SecureBytes, KdfParams,
/// password vault locking behaviour, and model serialization.
///
/// For integration tests that invoke the C library run:
///   flutter test integration_test/
library;

import 'dart:typed_data';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/crypto/native_bindings.dart';
import 'package:encrypted_files/crypto/secure_memory.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/database/models/log_entry.dart';
import 'package:encrypted_files/database/models/vault_model.dart';
import 'package:encrypted_files/database/models/virtual_folder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ─── AppConstants ────────────────────────────────────────────────────────
  group('AppConstants', () {
    test('key size is 32 bytes (256-bit)', () {
      expect(AppConstants.keySize, 32);
    });

    test('salt size is 16 bytes', () {
      expect(AppConstants.saltSize, 16);
    });

    test('nonce size is 24 bytes (XChaCha20)', () {
      expect(AppConstants.nonceSize, 24);
    });

    test('MAC size is 16 bytes (Poly1305)', () {
      expect(AppConstants.macSize, 16);
    });

    test('blind index size equals key size', () {
      expect(AppConstants.blindSize, AppConstants.keySize);
    });

    test('magic string is 8 bytes', () {
      expect(AppConstants.magic.length, 8);
    });

    test('default chunk size is in allowed list', () {
      expect(
        AppConstants.allowedChunkSizes.contains(AppConstants.defaultChunkBytes),
        isTrue,
      );
    });

    test('allowed chunk sizes are ordered ascending', () {
      for (var i = 1; i < AppConstants.allowedChunkSizes.length; i++) {
        expect(
          AppConstants.allowedChunkSizes[i] >
              AppConstants.allowedChunkSizes[i - 1],
          isTrue,
          reason: 'Chunk size list should be ascending',
        );
      }
    });

    test('Argon2 memory is at least 8 MiB', () {
      expect(AppConstants.argon2MemBlocks * 1024, greaterThanOrEqualTo(8 * 1024 * 1024));
    });

    test('unrecognized password delay is positive', () {
      expect(AppConstants.unrecognizedPasswordDelaySec, greaterThan(0));
    });

    test('log max rows is positive', () {
      expect(AppConstants.maxLogEntries, greaterThan(0));
    });
  });

  // ─── SecureBytes ─────────────────────────────────────────────────────────
  group('SecureBytes', () {
    test('holds bytes and returns them', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final sb = SecureBytes(data);
      expect(sb.bytes, equals([1, 2, 3, 4]));
      expect(sb.isWiped, isFalse);
    });

    test('wipe zeroes bytes and sets isWiped', () {
      final data = Uint8List.fromList([0xFF, 0xFF]);
      final sb = SecureBytes(data);
      sb.wipe();
      expect(sb.isWiped, isTrue);
      // The underlying array should be zeroed.
      expect(data, equals([0, 0]));
    });

    test('accessing bytes after wipe throws StateError', () {
      final sb = SecureBytes(Uint8List(4));
      sb.wipe();
      expect(() => sb.bytes, throwsStateError);
    });

    test('copy creates independent SecureBytes', () {
      final data = Uint8List.fromList([10, 20, 30]);
      final sb = SecureBytes(data);
      final copy = sb.copy();
      sb.wipe();
      // Copy should still be accessible.
      expect(copy.bytes, equals([10, 20, 30]));
    });

    test('double wipe is idempotent', () {
      final sb = SecureBytes(Uint8List(4));
      sb.wipe();
      expect(() => sb.wipe(), returnsNormally);
    });
  });

  // ─── SecureMemory ────────────────────────────────────────────────────────
  group('SecureMemory', () {
    test('track registers SecureBytes', () {
      final mem = SecureMemory();
      final data = Uint8List.fromList([1, 2, 3]);
      final sb = mem.track(data);
      expect(sb.bytes, equals([1, 2, 3]));
    });

    test('wipeAll zeroes all tracked bytes', () {
      final mem = SecureMemory();
      final d1 = Uint8List.fromList([0xAA, 0xBB]);
      final d2 = Uint8List.fromList([0xCC, 0xDD]);
      mem.track(d1);
      mem.track(d2);
      mem.wipeAll();
      expect(d1, equals([0, 0]));
      expect(d2, equals([0, 0]));
    });

    test('untrack wipes and removes from pool', () {
      final mem = SecureMemory();
      final data = Uint8List.fromList([5, 6, 7]);
      final sb = mem.track(data);
      mem.untrack(sb);
      expect(sb.isWiped, isTrue);
      // wipeAll on empty pool should not throw.
      expect(() => mem.wipeAll(), returnsNormally);
    });

    test('wipeAll after untrack does not double-wipe', () {
      final mem = SecureMemory();
      final data = Uint8List(8);
      final sb = mem.track(data);
      mem.untrack(sb);
      expect(() => mem.wipeAll(), returnsNormally);
    });
  });

  // ─── KdfParams ───────────────────────────────────────────────────────────
  group('KdfParams', () {
    test('default params match AppConstants', () {
      const p = KdfParams();
      expect(p.memBlocks, AppConstants.argon2MemBlocks);
      expect(p.passes, AppConstants.argon2Passes);
      expect(p.lanes, AppConstants.argon2Lanes);
    });

    test('custom params are stored correctly', () {
      const p = KdfParams(memBlocks: 32768, passes: 4, lanes: 2);
      expect(p.memBlocks, 32768);
      expect(p.passes, 4);
      expect(p.lanes, 2);
    });
  });

  // ─── LogLevel enum ───────────────────────────────────────────────────────
  group('LogLevel', () {
    test('all levels exist', () {
      expect(LogLevel.values.length, 4);
      expect(LogLevel.values, containsAll([
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
      ]));
    });
  });

  // ─── MediaKind detection via EncryptedFileRef ─────────────────────────
  group('EncryptedFileRef.mediaKind', () {
    EncryptedFileRef makeRef({String? mime, String? realName}) {
      return EncryptedFileRef(
        id: 'test-id',
        vaultId: 'v1',
        diskPath: '/tmp/fake.bin',
        fakeName: 'fake.bin',
        realNameEncrypted: Uint8List(0),
        mimeEncrypted: Uint8List(0),
        fileBlindTag: Uint8List(32),
        sizeBytes: 0,
        folderId: null,
        sortIndex: 0,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        realName: realName,
        mimeType: mime,
      );
    }

    test('image by mime', () {
      expect(makeRef(mime: 'image/png').mediaKind, MediaKind.image);
      expect(makeRef(mime: 'image/webp').mediaKind, MediaKind.image);
    });

    test('image by extension', () {
      expect(makeRef(realName: 'photo.jpg').mediaKind, MediaKind.image);
      expect(makeRef(realName: 'photo.jpeg').mediaKind, MediaKind.image);
      expect(makeRef(realName: 'photo.gif').mediaKind, MediaKind.image);
      expect(makeRef(realName: 'photo.bmp').mediaKind, MediaKind.image);
      expect(makeRef(realName: 'photo.webp').mediaKind, MediaKind.image);
    });

    test('audio by mime', () {
      expect(makeRef(mime: 'audio/mp3').mediaKind, MediaKind.audio);
      expect(makeRef(mime: 'audio/flac').mediaKind, MediaKind.audio);
    });

    test('audio by extension', () {
      expect(makeRef(realName: 'track.mp3').mediaKind, MediaKind.audio);
      expect(makeRef(realName: 'track.wav').mediaKind, MediaKind.audio);
      expect(makeRef(realName: 'track.m4a').mediaKind, MediaKind.audio);
      expect(makeRef(realName: 'track.ogg').mediaKind, MediaKind.audio);
      expect(makeRef(realName: 'track.flac').mediaKind, MediaKind.audio);
    });

    test('video by mime', () {
      expect(makeRef(mime: 'video/mp4').mediaKind, MediaKind.video);
      expect(makeRef(mime: 'video/webm').mediaKind, MediaKind.video);
    });

    test('video by extension', () {
      expect(makeRef(realName: 'clip.mp4').mediaKind, MediaKind.video);
      expect(makeRef(realName: 'clip.mkv').mediaKind, MediaKind.video);
      expect(makeRef(realName: 'clip.avi').mediaKind, MediaKind.video);
      expect(makeRef(realName: 'clip.mov').mediaKind, MediaKind.video);
    });

    test('document by mime', () {
      expect(makeRef(mime: 'application/pdf').mediaKind, MediaKind.document);
      expect(makeRef(mime: 'text/plain').mediaKind, MediaKind.document);
    });

    test('document by extension', () {
      expect(makeRef(realName: 'doc.pdf').mediaKind, MediaKind.document);
      expect(makeRef(realName: 'doc.txt').mediaKind, MediaKind.document);
      expect(makeRef(realName: 'doc.doc').mediaKind, MediaKind.document);
      expect(makeRef(realName: 'doc.xls').mediaKind, MediaKind.document);
    });

    test('other for unknown', () {
      expect(makeRef(realName: 'archive.zip').mediaKind, MediaKind.other);
      expect(makeRef(mime: 'application/octet-stream').mediaKind, MediaKind.other);
    });
  });

  // ─── EncryptedFileRef serialization ──────────────────────────────────────
  group('EncryptedFileRef.toMap / fromMap', () {
    test('round-trips correctly', () {
      final now = DateTime.utc(2025, 1, 15, 10, 30);
      final ref = EncryptedFileRef(
        id: 'abc-123',
        vaultId: 'vault-001',
        diskPath: '/data/secure/abc.jpg',
        fakeName: 'abc.jpg',
        realNameEncrypted: Uint8List.fromList([1, 2, 3]),
        mimeEncrypted: Uint8List.fromList([4, 5, 6]),
        fileBlindTag: Uint8List(32),
        sizeBytes: 1024,
        folderId: 'folder-xyz',
        sortIndex: 3,
        createdAt: now,
        modifiedAt: now,
      );

      final map = ref.toMap();
      final restored = EncryptedFileRef.fromMap(map);

      expect(restored.id, ref.id);
      expect(restored.vaultId, ref.vaultId);
      expect(restored.diskPath, ref.diskPath);
      expect(restored.fakeName, ref.fakeName);
      expect(restored.sizeBytes, ref.sizeBytes);
      expect(restored.folderId, ref.folderId);
      expect(restored.sortIndex, ref.sortIndex);
      expect(restored.createdAt, ref.createdAt);
      expect(restored.modifiedAt, ref.modifiedAt);
    });

    test('copyWith preserves unchanged fields', () {
      final ref = EncryptedFileRef(
        id: 'x',
        vaultId: 'v',
        diskPath: '/foo',
        fakeName: 'foo.bin',
        realNameEncrypted: Uint8List(0),
        mimeEncrypted: Uint8List(0),
        fileBlindTag: Uint8List(32),
        sizeBytes: 500,
        folderId: null,
        sortIndex: 0,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
      final updated = ref.copyWith(sizeBytes: 999, fakeName: 'bar.bin');
      expect(updated.id, ref.id);
      expect(updated.sizeBytes, 999);
      expect(updated.fakeName, 'bar.bin');
      expect(updated.diskPath, ref.diskPath);
    });
  });

  // ─── VaultModel serialization ─────────────────────────────────────────
  group('VaultModel.toMap / fromMap', () {
    test('round-trips correctly', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final blind = Uint8List.fromList(List.generate(32, (i) => i * 2));
      final kdf = const KdfParams(memBlocks: 16384, passes: 2, lanes: 1);
      final now = DateTime.utc(2025, 6, 1);

      final vault = VaultModel(
        id: 'vault-id',
        salt: salt,
        blindIndex: blind,
        kdf: kdf,
        createdAt: now,
      );

      final map = vault.toMap();
      final restored = VaultModel.fromMap(map);

      expect(restored.id, vault.id);
      expect(restored.salt, vault.salt);
      expect(restored.blindIndex, vault.blindIndex);
      expect(restored.kdf.memBlocks, kdf.memBlocks);
      expect(restored.kdf.passes, kdf.passes);
      expect(restored.kdf.lanes, kdf.lanes);
      expect(restored.createdAt, vault.createdAt);
    });
  });

  // ─── VirtualFolder serialization ─────────────────────────────────────
  group('VirtualFolder.toMap / fromMap', () {
    test('round-trips correctly', () {
      final now = DateTime.utc(2025, 3, 20);
      final folder = VirtualFolder(
        id: 'f1',
        vaultId: 'v1',
        nameEncrypted: [10, 20, 30],
        parentId: null,
        sortIndex: 0,
        createdAt: now,
        modifiedAt: now,
        name: 'Photos',
      );

      final map = folder.toMap();
      final restored = VirtualFolder.fromMap(map);

      expect(restored.id, folder.id);
      expect(restored.vaultId, folder.vaultId);
      expect(restored.nameEncrypted, folder.nameEncrypted);
      expect(restored.parentId, isNull);
      expect(restored.sortIndex, 0);
    });

    test('copyWith updates correctly', () {
      final folder = VirtualFolder(
        id: 'f2',
        vaultId: 'v2',
        nameEncrypted: [1, 2],
        parentId: null,
        sortIndex: 0,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        name: 'Old Name',
        fileCount: 5,
      );
      final updated = folder.copyWith(name: 'New Name', fileCount: 10);
      expect(updated.name, 'New Name');
      expect(updated.fileCount, 10);
      expect(updated.id, folder.id);
    });
  });

  // ─── LogEntry serialization ───────────────────────────────────────────
  group('LogEntry.toMap / fromMap', () {
    test('round-trips all log levels', () {
      for (final level in LogLevel.values) {
        final entry = LogEntry(
          id: null,
          level: level,
          tag: 'TestTag',
          message: 'Test message for $level',
          createdAt: DateTime.utc(2025, 1, 1),
        );
        final map = entry.toMap();
        final restored = LogEntry.fromMap({...map, 'id': 42});
        expect(restored.level, level);
        expect(restored.tag, entry.tag);
        expect(restored.message, entry.message);
      }
    });

    test('unknown level falls back to info', () {
      final entry = LogEntry.fromMap({
        'id': 1,
        'level': 'nonexistent',
        'tag': 'T',
        'message': 'M',
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(entry.level, LogLevel.info);
    });
  });

  // ─── Blind index constant-time equality ───────────────────────────────
  group('Constant-time comparison (pure Dart)', () {
    bool constantTimeEq(List<int> a, List<int> b) {
      if (a.length != b.length) return false;
      var diff = 0;
      for (var i = 0; i < a.length; i++) {
        diff |= a[i] ^ b[i];
      }
      return diff == 0;
    }

    test('equal lists return true', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([1, 2, 3, 4]);
      expect(constantTimeEq(a, b), isTrue);
    });

    test('different lists return false', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([1, 2, 3, 5]);
      expect(constantTimeEq(a, b), isFalse);
    });

    test('different lengths return false', () {
      expect(constantTimeEq([1, 2], [1, 2, 3]), isFalse);
    });

    test('empty lists are equal', () {
      expect(constantTimeEq([], []), isTrue);
    });

    test('all-zero vs non-zero', () {
      expect(constantTimeEq(List.filled(32, 0), List.filled(32, 1)), isFalse);
    });
  });

  // ─── SortMode enum ───────────────────────────────────────────────────
  group('SortMode', () {
    test('all sort modes exist', () {
      expect(SortMode.values, contains(SortMode.manual));
      expect(SortMode.values, contains(SortMode.nameAsc));
      expect(SortMode.values, contains(SortMode.nameDesc));
      expect(SortMode.values, contains(SortMode.createdAsc));
      expect(SortMode.values, contains(SortMode.createdDesc));
      expect(SortMode.values, contains(SortMode.modifiedAsc));
      expect(SortMode.values, contains(SortMode.modifiedDesc));
    });
  });

  // ─── AppConstants: magic string format ───────────────────────────────
  group('AppConstants.magic', () {
    test('starts with EF', () {
      expect(AppConstants.magic.startsWith('EF'), isTrue);
    });

    test('contains version indicator', () {
      expect(AppConstants.magic.contains('v'), isTrue);
    });

    test('is exactly 8 bytes when encoded', () {
      expect(AppConstants.magic.codeUnits.length, 8);
    });
  });
}
