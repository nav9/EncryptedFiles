import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/crypto/native_bindings.dart';
import 'package:encrypted_files/crypto/secure_memory.dart';
import 'package:ffi/ffi.dart';
import 'package:uuid/uuid.dart';

class DerivedKeys {
  DerivedKeys({
    required this.master,
    required this.enc,
    required this.blind,
    required this.blindIndex,
    required this.salt,
    required this.kdf,
  });

  final SecureBytes master;
  final SecureBytes enc;
  final SecureBytes blind;
  final Uint8List blindIndex;
  final Uint8List salt;
  final KdfParams kdf;

  void wipe() {
    master.wipe();
    enc.wipe();
    blind.wipe();
  }
}

class DecryptHeaderResult {
  DecryptHeaderResult({
    required this.realName,
    required this.mimeType,
    required this.plaintextSize,
    required this.fileBlindTag,
  });

  final String realName;
  final String mimeType;
  final int plaintextSize;
  final Uint8List fileBlindTag;
}

class ProbeResult {
  ProbeResult({
    required this.isEncryptedFile,
    this.salt,
    this.kdf,
    this.chunkSize,
    this.fileBlindTag,
  });

  final bool isEncryptedFile;
  final Uint8List? salt;
  final KdfParams? kdf;
  final int? chunkSize;
  final Uint8List? fileBlindTag;
}

class CryptoService {
  CryptoService(this._bindings);

  final NativeBindings _bindings;
  final _uuid = const Uuid();

  NativeBindings get bindings => _bindings;

  Uint8List randomBytes(int length) {
    final ptr = malloc<Uint8>(length);
    try {
      _bindings.check(_bindings.secureRandom(ptr, length), 'secureRandom');
      return Uint8List.fromList(ptr.asTypedList(length));
    } finally {
      _bindings.wipeAndFree(ptr, length);
    }
  }

  DerivedKeys deriveFromPassword(
    String password,
    Uint8List salt, {
    KdfParams kdf = const KdfParams(),
    SecureMemory? memory,
  }) {
    if (password.isEmpty) {
      throw EfAuthException('Password must not be empty');
    }
    if (salt.length != AppConstants.saltSize) {
      throw EfCryptoException('Invalid salt size');
    }

    final passBytes = Uint8List.fromList(utf8.encode(password));
    final passPtr = _bindings.bytesToNative(passBytes);
    final saltPtr = _bindings.bytesToNative(salt);
    final masterPtr = malloc<Uint8>(AppConstants.keySize);
    final encPtr = malloc<Uint8>(AppConstants.keySize);
    final blindPtr = malloc<Uint8>(AppConstants.keySize);
    final blindIndexPtr = malloc<Uint8>(AppConstants.blindSize);
    final paramsPtr = malloc<EfKdfParamsNative>();

    try {
      paramsPtr.ref
        ..memBlocks = kdf.memBlocks
        ..passes = kdf.passes
        ..lanes = kdf.lanes;

      _bindings.check(
        _bindings.deriveMasterKey(
          passPtr,
          passBytes.length,
          saltPtr,
          paramsPtr,
          masterPtr,
        ),
        'deriveMasterKey',
      );
      _bindings.deriveSubkeys(masterPtr, encPtr, blindPtr);
      _bindings.computeBlindIndex(blindPtr, blindIndexPtr);

      final master = SecureBytes(
        Uint8List.fromList(masterPtr.asTypedList(AppConstants.keySize)),
      );
      final enc = SecureBytes(
        Uint8List.fromList(encPtr.asTypedList(AppConstants.keySize)),
      );
      final blind = SecureBytes(
        Uint8List.fromList(blindPtr.asTypedList(AppConstants.keySize)),
      );
      final blindIndex =
          Uint8List.fromList(blindIndexPtr.asTypedList(AppConstants.blindSize));

      memory?.track(master.bytes);
      // Re-wrap tracked copies carefully: track clones.
      final trackedMaster = memory?.track(Uint8List.fromList(master.bytes)) ?? master;
      final trackedEnc = memory?.track(Uint8List.fromList(enc.bytes)) ?? enc;
      final trackedBlind = memory?.track(Uint8List.fromList(blind.bytes)) ?? blind;
      master.wipe();
      enc.wipe();
      blind.wipe();

      return DerivedKeys(
        master: trackedMaster,
        enc: trackedEnc,
        blind: trackedBlind,
        blindIndex: blindIndex,
        salt: Uint8List.fromList(salt),
        kdf: kdf,
      );
    } finally {
      for (var i = 0; i < passBytes.length; i++) {
        passBytes[i] = 0;
      }
      _bindings.wipeAndFree(passPtr, passBytes.length);
      malloc.free(saltPtr);
      _bindings.wipeAndFree(masterPtr, AppConstants.keySize);
      _bindings.wipeAndFree(encPtr, AppConstants.keySize);
      _bindings.wipeAndFree(blindPtr, AppConstants.keySize);
      malloc.free(blindIndexPtr);
      malloc.free(paramsPtr);
    }
  }

  Uint8List fileBlindTag(DerivedKeys keys, {Uint8List? fileId}) {
    final id = fileId ?? randomBytes(16);
    final blindPtr = _bindings.bytesToNative(keys.blind.bytes);
    final idPtr = _bindings.bytesToNative(id);
    final outPtr = malloc<Uint8>(AppConstants.blindSize);
    try {
      _bindings.computeFileBlindTag(blindPtr, idPtr, outPtr);
      return Uint8List.fromList(outPtr.asTypedList(AppConstants.blindSize));
    } finally {
      malloc.free(blindPtr);
      malloc.free(idPtr);
      malloc.free(outPtr);
    }
  }

  /// Verifies that [path] is an EncryptedFiles file belonging to [keys] by
  /// attempting to decrypt its (small) encrypted header — without touching the
  /// file payload. Returns true if the file belongs to this password.
  bool verifyFileBelongs(String path, DerivedKeys keys) {
    final pathPtr = path.toNativeUtf8();
    final blindPtr = _bindings.bytesToNative(keys.blind.bytes);
    final encPtr = _bindings.bytesToNative(keys.enc.bytes);
    try {
      final rc = _bindings.verifyFileBlind(pathPtr, blindPtr, encPtr);
      return rc == 0;
    } catch (_) {
      return false;
    } finally {
      malloc.free(pathPtr);
      _bindings.wipeAndFree(blindPtr, AppConstants.keySize);
      _bindings.wipeAndFree(encPtr, AppConstants.keySize);
    }
  }

  /// Opens the encrypted file at [path] and reads its header metadata (real
  /// name, MIME type, plaintext size, blind tag) without decrypting the
  /// payload. Returns null if the file is not an EncryptedFiles file or does
  /// not belong to [keys].
  DecryptHeaderResult? decryptHeader(String path, DerivedKeys keys) {
    final pathPtr = path.toNativeUtf8();
    final encPtr = _bindings.bytesToNative(keys.enc.bytes);
    final chunkPtr = malloc<Uint32>();
    final namePtr = malloc<Uint8>(512).cast<Utf8>();
    final mimePtr = malloc<Uint8>(128).cast<Utf8>();
    final sizePtr = malloc<Uint64>();
    final tagPtr = malloc<Uint8>(AppConstants.blindSize);
    Pointer<Void> ctx = nullptr;
    try {
      ctx = _bindings.decryptBegin(
        pathPtr,
        encPtr,
        chunkPtr,
        namePtr,
        512,
        mimePtr,
        128,
        sizePtr,
        tagPtr,
      );
      if (ctx == nullptr) {
        return null;
      }
      final name = namePtr.toDartString();
      final mime = mimePtr.toDartString();
      return DecryptHeaderResult(
        realName: name,
        mimeType: mime,
        plaintextSize: sizePtr.value,
        fileBlindTag:
            Uint8List.fromList(tagPtr.asTypedList(AppConstants.blindSize)),
      );
    } finally {
      if (ctx != nullptr) {
        _bindings.decryptAbort(ctx);
      }
      malloc.free(pathPtr);
      _bindings.wipeAndFree(encPtr, AppConstants.keySize);
      malloc.free(chunkPtr);
      malloc.free(namePtr);
      malloc.free(mimePtr);
      malloc.free(sizePtr);
      malloc.free(tagPtr);
    }
  }

  String newFileId() => _uuid.v4();

  Future<void> encryptFile({
    required String inputPath,
    required String outputPath,
    required DerivedKeys keys,
    required String realName,
    required String mimeType,
    required Uint8List fileBlindTag,
    required int chunkSize,
  }) async {
    final inPtr = inputPath.toNativeUtf8();
    final outPtr = outputPath.toNativeUtf8();
    final namePtr = realName.toNativeUtf8();
    final mimePtr = mimeType.toNativeUtf8();
    final encPtr = _bindings.bytesToNative(keys.enc.bytes);
    final saltPtr = _bindings.bytesToNative(keys.salt);
    final tagPtr = _bindings.bytesToNative(fileBlindTag);
    final paramsPtr = malloc<EfKdfParamsNative>();
    try {
      paramsPtr.ref
        ..memBlocks = keys.kdf.memBlocks
        ..passes = keys.kdf.passes
        ..lanes = keys.kdf.lanes;
      final rc = _bindings.encryptFile(
        inPtr,
        outPtr,
        encPtr,
        saltPtr,
        paramsPtr,
        chunkSize,
        namePtr,
        mimePtr,
        tagPtr,
      );
      _bindings.check(rc, 'encryptFile');
    } finally {
      malloc.free(inPtr);
      malloc.free(outPtr);
      malloc.free(namePtr);
      malloc.free(mimePtr);
      _bindings.wipeAndFree(encPtr, AppConstants.keySize);
      malloc.free(saltPtr);
      malloc.free(tagPtr);
      malloc.free(paramsPtr);
    }
  }

  /// Stream-encrypt from an open source by reading chunk callbacks.
  Future<void> encryptStream({
    required String outputPath,
    required DerivedKeys keys,
    required String realName,
    required String mimeType,
    required Uint8List fileBlindTag,
    required int chunkSize,
    required int plaintextSize,
    required Stream<List<int>> source,
  }) async {
    final outPtr = outputPath.toNativeUtf8();
    final namePtr = realName.toNativeUtf8();
    final mimePtr = mimeType.toNativeUtf8();
    final encPtr = _bindings.bytesToNative(keys.enc.bytes);
    final saltPtr = _bindings.bytesToNative(keys.salt);
    final tagPtr = _bindings.bytesToNative(fileBlindTag);
    final paramsPtr = malloc<EfKdfParamsNative>();
    Pointer<Void> ctx = nullptr;
    try {
      paramsPtr.ref
        ..memBlocks = keys.kdf.memBlocks
        ..passes = keys.kdf.passes
        ..lanes = keys.kdf.lanes;
      ctx = _bindings.encryptBegin(
        outPtr,
        encPtr,
        saltPtr,
        paramsPtr,
        chunkSize,
        namePtr,
        mimePtr,
        plaintextSize,
        tagPtr,
      );
      if (ctx == nullptr) {
        throw EfCryptoException('encryptBegin failed');
      }
      await for (final chunk in source) {
        if (chunk.isEmpty) {
          continue;
        }
        final dataPtr = _bindings.bytesToNative(chunk);
        try {
          _bindings.check(
            _bindings.encryptUpdate(ctx, dataPtr, chunk.length),
            'encryptUpdate',
          );
        } finally {
          _bindings.wipeAndFree(dataPtr, chunk.length);
        }
      }
      _bindings.check(_bindings.encryptFinish(ctx), 'encryptFinish');
      ctx = nullptr;
    } catch (e) {
      if (ctx != nullptr) {
        _bindings.encryptAbort(ctx);
        ctx = nullptr;
      }
      try {
        File(outputPath).deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      malloc.free(outPtr);
      malloc.free(namePtr);
      malloc.free(mimePtr);
      _bindings.wipeAndFree(encPtr, AppConstants.keySize);
      malloc.free(saltPtr);
      malloc.free(tagPtr);
      malloc.free(paramsPtr);
    }
  }

  Future<void> decryptFile({
    required String inputPath,
    required String outputPath,
    required DerivedKeys keys,
  }) async {
    final inPtr = inputPath.toNativeUtf8();
    final outPtr = outputPath.toNativeUtf8();
    final encPtr = _bindings.bytesToNative(keys.enc.bytes);
    try {
      _bindings.check(
        _bindings.decryptFile(inPtr, outPtr, encPtr),
        'decryptFile',
      );
    } finally {
      malloc.free(inPtr);
      malloc.free(outPtr);
      _bindings.wipeAndFree(encPtr, AppConstants.keySize);
    }
  }

  Future<void> secureDelete(String path) async {
    final ptr = path.toNativeUtf8();
    try {
      _bindings.check(_bindings.secureDelete(ptr), 'secureDelete');
    } finally {
      malloc.free(ptr);
    }
  }

  int suggestChunkSize(int availableRamKib) {
    return _bindings.suggestChunkSize(availableRamKib);
  }

  ProbeResult probe(String path) {
    final pathPtr = path.toNativeUtf8();
    final saltPtr = malloc<Uint8>(AppConstants.saltSize);
    final paramsPtr = malloc<EfKdfParamsNative>();
    final chunkPtr = malloc<Uint32>();
    final blindPtr = malloc<Uint8>(AppConstants.blindSize);
    final isEfPtr = malloc<Int32>();
    try {
      final rc = _bindings.probeFile(
        pathPtr,
        saltPtr,
        paramsPtr,
        chunkPtr,
        blindPtr,
        isEfPtr,
      );
      if (rc != 0 && rc != -8) {
        _bindings.check(rc, 'probeFile');
      }
      final isEf = isEfPtr.value != 0;
      if (!isEf) {
        return ProbeResult(isEncryptedFile: false);
      }
      return ProbeResult(
        isEncryptedFile: true,
        salt: Uint8List.fromList(saltPtr.asTypedList(AppConstants.saltSize)),
        kdf: KdfParams(
          memBlocks: paramsPtr.ref.memBlocks,
          passes: paramsPtr.ref.passes,
          lanes: paramsPtr.ref.lanes,
        ),
        chunkSize: chunkPtr.value,
        fileBlindTag:
            Uint8List.fromList(blindPtr.asTypedList(AppConstants.blindSize)),
      );
    } finally {
      malloc.free(pathPtr);
      malloc.free(saltPtr);
      malloc.free(paramsPtr);
      malloc.free(chunkPtr);
      malloc.free(blindPtr);
      malloc.free(isEfPtr);
    }
  }
}
