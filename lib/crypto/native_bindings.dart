import 'dart:ffi';
import 'dart:io';
import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/exceptions.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

final class EfKdfParamsNative extends Struct {
  @Uint32()
  external int memBlocks;
  @Uint32()
  external int passes;
  @Uint32()
  external int lanes;
}

typedef DeriveMasterNative = Int32 Function(
  Pointer<Uint8> password,
  IntPtr passwordLen,
  Pointer<Uint8> salt,
  Pointer<EfKdfParamsNative> params,
  Pointer<Uint8> outKey,
);
typedef DeriveMasterDart = int Function(
  Pointer<Uint8> password,
  int passwordLen,
  Pointer<Uint8> salt,
  Pointer<EfKdfParamsNative> params,
  Pointer<Uint8> outKey,
);

typedef VoidKey2Native = Void Function(
  Pointer<Uint8> master,
  Pointer<Uint8> enc,
  Pointer<Uint8> blind,
);
typedef VoidKey2Dart = void Function(
  Pointer<Uint8> master,
  Pointer<Uint8> enc,
  Pointer<Uint8> blind,
);

typedef BlindNative = Void Function(Pointer<Uint8> blindKey, Pointer<Uint8> out);
typedef BlindDart = void Function(Pointer<Uint8> blindKey, Pointer<Uint8> out);

typedef FileBlindNative = Void Function(
  Pointer<Uint8> blindKey,
  Pointer<Uint8> fileId,
  Pointer<Uint8> out,
);
typedef FileBlindDart = void Function(
  Pointer<Uint8> blindKey,
  Pointer<Uint8> fileId,
  Pointer<Uint8> out,
);

typedef VerifyFileBlindNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Uint8> blindKey,
  Pointer<Uint8> encKey,
);
typedef VerifyFileBlindDart = int Function(
  Pointer<Utf8> path,
  Pointer<Uint8> blindKey,
  Pointer<Uint8> encKey,
);

typedef EncryptFileNative = Int32 Function(
  Pointer<Utf8> inputPath,
  Pointer<Utf8> outputPath,
  Pointer<Uint8> encKey,
  Pointer<Uint8> salt,
  Pointer<EfKdfParamsNative> params,
  Uint32 chunkSize,
  Pointer<Utf8> realName,
  Pointer<Utf8> mimeType,
  Pointer<Uint8> fileBlindTag,
);
typedef EncryptFileDart = int Function(
  Pointer<Utf8> inputPath,
  Pointer<Utf8> outputPath,
  Pointer<Uint8> encKey,
  Pointer<Uint8> salt,
  Pointer<EfKdfParamsNative> params,
  int chunkSize,
  Pointer<Utf8> realName,
  Pointer<Utf8> mimeType,
  Pointer<Uint8> fileBlindTag,
);

typedef DecryptFileNative = Int32 Function(
  Pointer<Utf8> inputPath,
  Pointer<Utf8> outputPath,
  Pointer<Uint8> encKey,
);
typedef DecryptFileDart = int Function(
  Pointer<Utf8> inputPath,
  Pointer<Utf8> outputPath,
  Pointer<Uint8> encKey,
);

typedef DecryptBeginNative = Pointer<Void> Function(
  Pointer<Utf8> inputPath,
  Pointer<Uint8> encKey,
  Pointer<Uint32> outChunkSize,
  Pointer<Utf8> outRealName,
  IntPtr realNameCap,
  Pointer<Utf8> outMime,
  IntPtr mimeCap,
  Pointer<Uint64> outPlaintextSize,
  Pointer<Uint8> outBlindTag,
);
typedef DecryptBeginDart = Pointer<Void> Function(
  Pointer<Utf8> inputPath,
  Pointer<Uint8> encKey,
  Pointer<Uint32> outChunkSize,
  Pointer<Utf8> outRealName,
  int realNameCap,
  Pointer<Utf8> outMime,
  int mimeCap,
  Pointer<Uint64> outPlaintextSize,
  Pointer<Uint8> outBlindTag,
);

typedef DecryptAbortNative = Void Function(Pointer<Void> ctx);
typedef DecryptAbortDart = void Function(Pointer<Void> ctx);

typedef SecureDeleteNative = Int32 Function(Pointer<Utf8> path);
typedef SecureDeleteDart = int Function(Pointer<Utf8> path);

typedef SuggestChunkNative = Uint32 Function(Uint64 availableRamKib);
typedef SuggestChunkDart = int Function(int availableRamKib);

typedef SecureRandomNative = Int32 Function(Pointer<Uint8> out, IntPtr len);
typedef SecureRandomDart = int Function(Pointer<Uint8> out, int len);

typedef SecureWipeNative = Void Function(Pointer<Void> ptr, IntPtr len);
typedef SecureWipeDart = void Function(Pointer<Void> ptr, int len);

typedef ProbeNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Uint8> outSalt,
  Pointer<EfKdfParamsNative> outParams,
  Pointer<Uint32> outChunk,
  Pointer<Uint8> outBlind,
  Pointer<Int32> outIsEf,
);
typedef ProbeDart = int Function(
  Pointer<Utf8> path,
  Pointer<Uint8> outSalt,
  Pointer<EfKdfParamsNative> outParams,
  Pointer<Uint32> outChunk,
  Pointer<Uint8> outBlind,
  Pointer<Int32> outIsEf,
);

typedef ServerStartNative = Pointer<Void> Function(
  Pointer<Uint8> encKey,
  Uint32 chunkOverride,
  Pointer<Int32> outPort,
);
typedef ServerStartDart = Pointer<Void> Function(
  Pointer<Uint8> encKey,
  int chunkOverride,
  Pointer<Int32> outPort,
);

typedef ServerRegisterNative = Int32 Function(
  Pointer<Void> server,
  Pointer<Utf8> path,
  Pointer<Utf8> outToken,
  IntPtr tokenCap,
  Pointer<Utf8> outUrl,
  IntPtr urlCap,
);
typedef ServerRegisterDart = int Function(
  Pointer<Void> server,
  Pointer<Utf8> path,
  Pointer<Utf8> outToken,
  int tokenCap,
  Pointer<Utf8> outUrl,
  int urlCap,
);

typedef ServerUnregisterNative = Void Function(Pointer<Void> server, Pointer<Utf8> token);
typedef ServerUnregisterDart = void Function(Pointer<Void> server, Pointer<Utf8> token);

typedef ServerStopNative = Void Function(Pointer<Void> server);
typedef ServerStopDart = void Function(Pointer<Void> server);

typedef ServerClearNative = Void Function(Pointer<Void> server);
typedef ServerClearDart = void Function(Pointer<Void> server);

typedef EncryptBeginNative = Pointer<Void> Function(
  Pointer<Utf8> outputPath,
  Pointer<Uint8> encKey,
  Pointer<Uint8> salt,
  Pointer<EfKdfParamsNative> params,
  Uint32 chunkSize,
  Pointer<Utf8> realName,
  Pointer<Utf8> mimeType,
  Uint64 plaintextSize,
  Pointer<Uint8> fileBlindTag,
);
typedef EncryptBeginDart = Pointer<Void> Function(
  Pointer<Utf8> outputPath,
  Pointer<Uint8> encKey,
  Pointer<Uint8> salt,
  Pointer<EfKdfParamsNative> params,
  int chunkSize,
  Pointer<Utf8> realName,
  Pointer<Utf8> mimeType,
  int plaintextSize,
  Pointer<Uint8> fileBlindTag,
);

typedef EncryptUpdateNative = Int32 Function(
  Pointer<Void> ctx,
  Pointer<Uint8> data,
  IntPtr len,
);
typedef EncryptUpdateDart = int Function(
  Pointer<Void> ctx,
  Pointer<Uint8> data,
  int len,
);

typedef EncryptFinishNative = Int32 Function(Pointer<Void> ctx);
typedef EncryptFinishDart = int Function(Pointer<Void> ctx);
typedef EncryptAbortNative = Void Function(Pointer<Void> ctx);
typedef EncryptAbortDart = void Function(Pointer<Void> ctx);

typedef AeadSealNative = Int32 Function(
  Pointer<Uint8> key,
  Pointer<Uint8> ad,
  IntPtr adLen,
  Pointer<Uint8> plain,
  IntPtr plainLen,
  Pointer<Uint8> out,
  IntPtr outCap,
  Pointer<IntPtr> outLen,
);
typedef AeadSealDart = int Function(
  Pointer<Uint8> key,
  Pointer<Uint8> ad,
  int adLen,
  Pointer<Uint8> plain,
  int plainLen,
  Pointer<Uint8> out,
  int outCap,
  Pointer<IntPtr> outLen,
);

typedef AeadOpenNative = Int32 Function(
  Pointer<Uint8> key,
  Pointer<Uint8> ad,
  IntPtr adLen,
  Pointer<Uint8> blob,
  IntPtr blobLen,
  Pointer<Uint8> out,
  IntPtr outCap,
  Pointer<IntPtr> outLen,
);
typedef AeadOpenDart = int Function(
  Pointer<Uint8> key,
  Pointer<Uint8> ad,
  int adLen,
  Pointer<Uint8> blob,
  int blobLen,
  Pointer<Uint8> out,
  int outCap,
  Pointer<IntPtr> outLen,
);

class NativeBindings {
  late final DynamicLibrary _lib;

  late final DeriveMasterDart deriveMasterKey;
  late final VoidKey2Dart deriveSubkeys;
  late final BlindDart computeBlindIndex;
  late final FileBlindDart computeFileBlindTag;
  late final VerifyFileBlindDart verifyFileBlind;
  late final EncryptFileDart encryptFile;
  late final DecryptFileDart decryptFile;
  late final DecryptBeginDart decryptBegin;
  late final DecryptAbortDart decryptAbort;
  late final SecureDeleteDart secureDelete;
  late final SuggestChunkDart suggestChunkSize;
  late final SecureRandomDart secureRandom;
  late final SecureWipeDart secureWipe;
  late final ProbeDart probeFile;
  late final ServerStartDart streamServerStart;
  late final ServerRegisterDart streamServerRegister;
  late final ServerUnregisterDart streamServerUnregister;
  late final ServerStopDart streamServerStop;
  late final ServerClearDart streamServerClearKeys;
  late final EncryptBeginDart encryptBegin;
  late final EncryptUpdateDart encryptUpdate;
  late final EncryptFinishDart encryptFinish;
  late final EncryptAbortDart encryptAbort;
  late final AeadSealDart aeadSeal;
  late final AeadOpenDart aeadOpen;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  void load() {
    if (_loaded) {
      return;
    }
    try {
      _lib = _openLibrary();
      deriveMasterKey = _lib.lookupFunction<DeriveMasterNative, DeriveMasterDart>('ef_derive_master_key');
      deriveSubkeys = _lib.lookupFunction<VoidKey2Native, VoidKey2Dart>('ef_derive_subkeys');
      computeBlindIndex = _lib.lookupFunction<BlindNative, BlindDart>('ef_compute_blind_index');
      computeFileBlindTag =
          _lib.lookupFunction<FileBlindNative, FileBlindDart>('ef_compute_file_blind_tag');
      verifyFileBlind =
          _lib.lookupFunction<VerifyFileBlindNative, VerifyFileBlindDart>('ef_verify_file_blind');
      encryptFile = _lib.lookupFunction<EncryptFileNative, EncryptFileDart>('ef_encrypt_file');
      decryptFile = _lib.lookupFunction<DecryptFileNative, DecryptFileDart>('ef_decrypt_file');
      decryptBegin =
          _lib.lookupFunction<DecryptBeginNative, DecryptBeginDart>('ef_decrypt_begin');
      decryptAbort =
          _lib.lookupFunction<DecryptAbortNative, DecryptAbortDart>('ef_decrypt_abort');
      secureDelete = _lib.lookupFunction<SecureDeleteNative, SecureDeleteDart>('ef_secure_delete');
      suggestChunkSize =
          _lib.lookupFunction<SuggestChunkNative, SuggestChunkDart>('ef_suggest_chunk_size');
      secureRandom = _lib.lookupFunction<SecureRandomNative, SecureRandomDart>('ef_secure_random');
      secureWipe = _lib.lookupFunction<SecureWipeNative, SecureWipeDart>('ef_secure_wipe');
      probeFile = _lib.lookupFunction<ProbeNative, ProbeDart>('ef_probe_file');
      streamServerStart =
          _lib.lookupFunction<ServerStartNative, ServerStartDart>('ef_stream_server_start');
      streamServerRegister =
          _lib.lookupFunction<ServerRegisterNative, ServerRegisterDart>('ef_stream_server_register');
      streamServerUnregister = _lib
          .lookupFunction<ServerUnregisterNative, ServerUnregisterDart>('ef_stream_server_unregister');
      streamServerStop =
          _lib.lookupFunction<ServerStopNative, ServerStopDart>('ef_stream_server_stop');
      streamServerClearKeys =
          _lib.lookupFunction<ServerClearNative, ServerClearDart>('ef_stream_server_clear_keys');
      encryptBegin = _lib.lookupFunction<EncryptBeginNative, EncryptBeginDart>('ef_encrypt_begin');
      encryptUpdate = _lib.lookupFunction<EncryptUpdateNative, EncryptUpdateDart>('ef_encrypt_update');
      encryptFinish = _lib.lookupFunction<EncryptFinishNative, EncryptFinishDart>('ef_encrypt_finish');
      encryptAbort = _lib.lookupFunction<EncryptAbortNative, EncryptAbortDart>('ef_encrypt_abort');
      aeadSeal = _lib.lookupFunction<AeadSealNative, AeadSealDart>('ef_aead_seal');
      aeadOpen = _lib.lookupFunction<AeadOpenNative, AeadOpenDart>('ef_aead_open');
      _loaded = true;
    } catch (e, st) {
      debugPrint('NativeBindings.load failed: $e\n$st');
      throw EfCryptoException('Failed to load native crypto library', cause: e);
    }
  }

  DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libencrypted_files_core.so');
    }
    if (Platform.isLinux) {
      try {
        return DynamicLibrary.open('libencrypted_files_core.so');
      } catch (_) {
        final exe = File(Platform.resolvedExecutable);
        final candidate = '${exe.parent.path}/lib/libencrypted_files_core.so';
        return DynamicLibrary.open(candidate);
      }
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('encrypted_files_core.dll');
    }
    if (Platform.isMacOS) {
      try {
        return DynamicLibrary.open('libencrypted_files_core.dylib');
      } catch (_) {
        final exe = File(Platform.resolvedExecutable);
        final candidate =
            '${exe.parent.path}/../Frameworks/libencrypted_files_core.dylib';
        return DynamicLibrary.open(candidate);
      }
    }
    throw EfCryptoException('Unsupported platform for native core');
  }

  Pointer<Uint8> bytesToNative(List<int> bytes) {
    final ptr = malloc<Uint8>(bytes.length);
    final view = ptr.asTypedList(bytes.length);
    view.setAll(0, bytes);
    return ptr;
  }

  void wipeAndFree(Pointer<Uint8> ptr, int len) {
    if (ptr == nullptr) {
      return;
    }
    try {
      secureWipe(ptr.cast(), len);
    } catch (_) {
      ptr.asTypedList(len).fillRange(0, len, 0);
    }
    malloc.free(ptr);
  }

  int check(int code, String op) {
    if (code == 0) {
      return code;
    }
    throw EfCryptoException('$op failed', code: code);
  }
}

class KdfParams {
  const KdfParams({
    this.memBlocks = AppConstants.argon2MemBlocks,
    this.passes = AppConstants.argon2Passes,
    this.lanes = AppConstants.argon2Lanes,
  });

  final int memBlocks;
  final int passes;
  final int lanes;
}
