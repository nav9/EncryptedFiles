import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/crypto/crypto_service.dart';
import 'package:encrypted_files/crypto/native_bindings.dart';
import 'package:encrypted_files/crypto/secure_memory.dart';
import 'package:encrypted_files/database/database_service.dart';
import 'package:encrypted_files/database/models/vault_model.dart';
import 'package:ffi/ffi.dart';

class ActiveSession {
  ActiveSession({
    required this.vault,
    required this.keys,
    this.isDecoy = false,
  });

  final VaultModel vault;
  final DerivedKeys keys;

  /// True when unlocked with the plausible-deniability (decoy) password.
  /// The UI should display a fake "corrupt bytes" result instead of real files.
  final bool isDecoy;
}

/// Manages password derivation, vault matching via blind index, and RAM wiping.
class PasswordVault {
  PasswordVault(this._crypto, this._db, this._memory);

  final CryptoService _crypto;
  final DatabaseService _db;
  final SecureMemory _memory;

  ActiveSession? _active;

  ActiveSession? get active => _active;
  bool get hasActivePassword => _active != null && !(_active?.isDecoy ?? false);
  NativeBindings get _bindings => _crypto.bindings;

  Future<ActiveSession?> unlock(String password) async {
    final vaults = await _db.listVaults();
    for (final vault in vaults) {
      DerivedKeys? keys;
      try {
        keys = _crypto.deriveFromPassword(
          password,
          vault.salt,
          kdf: vault.kdf,
          memory: _memory,
        );
        if (_constantTimeEquals(keys.blindIndex, vault.blindIndex)) {
          await clearActive();
          _active = ActiveSession(
            vault: vault,
            keys: keys,
            isDecoy: vault.isDecoy,
          );
          return _active;
        }
        keys.wipe();
      } catch (_) {
        keys?.wipe();
      }
    }
    return null;
  }

  Future<ActiveSession> createVault(String password, {KdfParams? kdf}) async {
    final params = kdf ?? const KdfParams();
    final salt = _crypto.randomBytes(AppConstants.saltSize);
    final keys = _crypto.deriveFromPassword(
      password,
      salt,
      kdf: params,
      memory: _memory,
    );
    final existing = await _db.findVaultByBlindIndex(keys.blindIndex);
    if (existing != null) {
      keys.wipe();
      final unlocked = await unlock(password);
      if (unlocked == null) {
        throw EfAuthException('Vault exists but could not unlock');
      }
      return unlocked;
    }

    final vault = VaultModel(
      id: _crypto.newFileId(),
      salt: salt,
      blindIndex: keys.blindIndex,
      kdf: params,
      createdAt: DateTime.now().toUtc(),
      isDecoy: false,
    );
    await _db.insertVault(vault);
    await clearActive();
    _active = ActiveSession(vault: vault, keys: keys);
    return _active!;
  }

  /// Creates a decoy vault that when unlocked will show a fake "corrupt bytes" result.
  Future<void> createDecoyVault(String decoyPassword, {KdfParams? kdf}) async {
    final params = kdf ?? const KdfParams();
    final salt = _crypto.randomBytes(AppConstants.saltSize);
    DerivedKeys? keys;
    try {
      keys = _crypto.deriveFromPassword(decoyPassword, salt, kdf: params);
      // Don't create if a vault already exists for this password.
      final existing = await _db.findVaultByBlindIndex(keys.blindIndex);
      if (existing != null) return;

      final vault = VaultModel(
        id: _crypto.newFileId(),
        salt: salt,
        blindIndex: keys.blindIndex,
        kdf: params,
        createdAt: DateTime.now().toUtc(),
        isDecoy: true,
      );
      await _db.insertVault(vault);
    } finally {
      keys?.wipe();
    }
  }

  Future<ActiveSession> unlockOrCreate(String password) async {
    final existing = await unlock(password);
    if (existing != null) {
      return existing;
    }
    return createVault(password);
  }

  Future<void> clearActive() async {
    final prev = _active;
    _active = null;
    prev?.keys.wipe();
    _memory.wipeAll();
  }

  Uint8List encryptMetadata(String plaintext) {
    final session = _requireActive();
    return _sealString(session.keys, plaintext);
  }

  String decryptMetadata(Uint8List blob) {
    final session = _requireActive();
    return _openString(session.keys, blob);
  }

  ActiveSession _requireActive() {
    final a = _active;
    if (a == null) {
      throw EfAuthException('No active password');
    }
    return a;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static final _ad = utf8.encode('EncryptedFiles/meta/v1');

  Uint8List _sealString(DerivedKeys keys, String plaintext) {
    final plain = Uint8List.fromList(utf8.encode(plaintext));
    final outCap = AppConstants.nonceSize + AppConstants.macSize + plain.length;
    final keyPtr = _bindings.bytesToNative(keys.enc.bytes);
    final adPtr = _bindings.bytesToNative(_ad);
    final plainPtr = _bindings.bytesToNative(plain);
    final outPtr = malloc<Uint8>(outCap);
    final outLenPtr = malloc<IntPtr>();
    try {
      _bindings.check(
        _bindings.aeadSeal(
          keyPtr,
          adPtr,
          _ad.length,
          plainPtr,
          plain.length,
          outPtr,
          outCap,
          outLenPtr,
        ),
        'aeadSeal',
      );
      final n = outLenPtr.value;
      return Uint8List.fromList(outPtr.asTypedList(n));
    } finally {
      for (var i = 0; i < plain.length; i++) {
        plain[i] = 0;
      }
      _bindings.wipeAndFree(keyPtr, AppConstants.keySize);
      malloc.free(adPtr);
      _bindings.wipeAndFree(plainPtr, plain.length);
      _bindings.wipeAndFree(outPtr, outCap);
      malloc.free(outLenPtr);
    }
  }

  String _openString(DerivedKeys keys, Uint8List blob) {
    final outCap = blob.length;
    final keyPtr = _bindings.bytesToNative(keys.enc.bytes);
    final adPtr = _bindings.bytesToNative(_ad);
    final blobPtr = _bindings.bytesToNative(blob);
    final outPtr = malloc<Uint8>(outCap);
    final outLenPtr = malloc<IntPtr>();
    try {
      _bindings.check(
        _bindings.aeadOpen(
          keyPtr,
          adPtr,
          _ad.length,
          blobPtr,
          blob.length,
          outPtr,
          outCap,
          outLenPtr,
        ),
        'aeadOpen',
      );
      final n = outLenPtr.value;
      final text = utf8.decode(outPtr.asTypedList(n));
      outPtr.asTypedList(n).fillRange(0, n, 0);
      return text;
    } finally {
      _bindings.wipeAndFree(keyPtr, AppConstants.keySize);
      malloc.free(adPtr);
      malloc.free(blobPtr);
      _bindings.wipeAndFree(outPtr, outCap);
      malloc.free(outLenPtr);
    }
  }
}
