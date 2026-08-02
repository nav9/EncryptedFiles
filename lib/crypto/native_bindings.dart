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

typedef _DeriveMasterNative = Int32 Function(
  Pointer<Uint8> password,
  IntPtr passwordLen,
  Pointer<Uint8> salt,
  Pointer<EfKdfParamsNative> params,
  Pointer<Uint8> outKey,
);
typedef _DeriveMasterDart = int Function(
  Pointer<Uint8> password,
  int passwordLen,
  Pointer<Uint8> salt,
  Pointer<EfKdfParamsNative> params,
  Pointer<Uint8> outKey,
);

typedef _VoidKey2Native = Void Function(
  Pointer<Uint8> master,
  Pointer<Uint8> enc,
  Pointer<Uint8> blind,
);
typedef _VoidKey2Dart = void Function(
  Pointer<Uint8> master,
  Pointer<Uint8> enc,
  Pointer<Uint8> blind,
);

typedef _BlindNative = Void Function(Pointer<Uint8> blindKey, Pointer<Uint8> out);
typedef _BlindDart = void Function(Pointer<Uint8> blindKey, Pointer<Uint8> out);

typedef _FileBlindNative = Void Function(
  Pointer<Uint8> blindKey,
  Pointer<Uint8> fileId,
  Pointer<Uint8> out,
);
typedef _FileBlindDart = void Function(
  Pointer<Uint8> blindKey,
  Pointer<Uint8> fileId,
  Pointer<Uint8> out,
);

typedef _EncryptFileNative = Int32 Function(
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
typedef _EncryptFileDart = int Function(
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

typedef _DecryptFileNative = Int32 Function(
  Pointer<Utf8> inputPath,
  Pointer<Utf8> outputPath,
  Pointer<Uint8> encKey,
);
typedef _DecryptFileDart = int Function(
  Pointer<Utf8> inputPath,
  Pointer<Utf8> outputPath,
  Pointer<Uint8> encKey,
);

typedef _SecureDeleteNative = Int32 Function(Pointer<Utf8> path);
typedef _SecureDeleteDart = int Function(Pointer<Utf8> path);

typedef _SuggestChunkNative = Uint32 Function(Uint64 availableRamKib);
typedef _SuggestChunkDart = int Function(int availableRamKib);

typedef _SecureRandomNative = Int32 Function(Pointer<Uint8> out, IntPtr len);
typedef _SecureRandomDart = int Function(Pointer<Uint8> out, int len);

typedef _SecureWipeNative = Void Function(Pointer<Void> ptr, IntPtr len);
typedef _SecureWipeDart = void Function(Pointer<Void> ptr, int len);

typedef _ProbeNative = Int32 Function(
  Pointer<Utf8> path,
  Pointer<Uint8> outSalt,
  Pointer<EfKdfParamsNative> outParams,
  Pointer<Uint32> outChunk,
  Pointer<Uint8> outBlind,
  Pointer<Int32> outIsEf,
);
typedef _ProbeDart = int Function(
  Pointer<Utf8> path,
  Pointer<Uint8> outSalt,
  Pointer<EfKdfParamsNative> outParams,
  Pointer<Uint32> outChunk,
  Pointer<Uint8> outBlind,
  Pointer<Int32> outIsEf,
);

typedef _ServerStartNative = Pointer<Void> Function(
  Pointer<Uint8> encKey,
  Uint32 chunkOverride,
  Pointer<Int32> outPort,
);
typedef _ServerStartDart = Pointer<Void> Function(
  Pointer<Uint8> encKey,
  int chunkOverride,
  Pointer<Int32> outPort,
);

typedef _ServerRegisterNative = Int32 Function(
  Pointer<Void> server,
  Pointer<Utf8> path,
  Pointer<Utf8> outToken,
  IntPtr tokenCap,
  Pointer<Utf8> outUrl,
  IntPtr urlCap,
);
typedef _ServerRegisterDart = int Function(
  Pointer<Void> server,
  Pointer<Utf8> path,
  Pointer<Utf8> outToken,
  int tokenCap,
  Pointer<Utf8> outUrl,
  int urlCap,
);

typedef _ServerUnregisterNative = Void Function(Pointer<Void> server, Pointer<Utf8> token);
typedef _ServerUnregisterDart = void Function(Pointer<Void> server, Pointer<Utf8> token);

typedef _ServerStopNative = Void Function(Pointer<Void> server);
typedef _ServerStopDart = void Function(Pointer<Void> server);

typedef _ServerClearNative = Void Function(Pointer<Void> server);
typedef _ServerClearDart = void Function(Pointer<Void> server);

typedef _EncryptBeginNative = Pointer<Void> Function(
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
typedef _EncryptBeginDart = Pointer<Void> Function(
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

typedef _EncryptUpdateNative = Int32 Function(
  Pointer<Void> ctx,
  Pointer<Uint8> data,
  IntPtr len,
);
typedef _EncryptUpdateDart = int Function(
  Pointer<Void> ctx,
  Pointer<Uint8> data,
  int len,
);

typedef _EncryptFinishNative = Int32 Function(Pointer<Void> ctx);
typedef _EncryptFinishDart = int Function(Pointer<Void> ctx);
typedef _EncryptAbortNative = Void Function(Pointer<Void> ctx);
typedef _EncryptAbortDart = void Function(Pointer<Void> ctx);

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

  late final _DeriveMasterDart deriveMasterKey;
  late final _VoidKey2Dart deriveSubkeys;
  late final _BlindDart computeBlindIndex;
  late final _FileBlindDart computeFileBlindTag;
  late final _EncryptFileDart encryptFile;
  late final _DecryptFileDart decryptFile;
  late final _SecureDeleteDart secureDelete;
  late final _SuggestChunkDart suggestChunkSize;
  late final _SecureRandomDart secureRandom;
  late final _SecureWipeDart secureWipe;
  late final _ProbeDart probeFile;
  late final _ServerStartDart streamServerStart;
  late final _ServerRegisterDart streamServerRegister;
  late final _ServerUnregisterDart streamServerUnregister;
  late final _ServerStopDart streamServerStop;
  late final _ServerClearDart streamServerClearKeys;
  late final _EncryptBeginDart encryptBegin;
  late final _EncryptUpdateDart encryptUpdate;
  late final _EncryptFinishDart encryptFinish;
  late final _EncryptAbortDart encryptAbort;
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
      deriveMasterKey = _lib.lookupFunction<_DeriveMasterNative, _DeriveMasterDart>('ef_derive_master_key');
      deriveSubkeys = _lib.lookupFunction<_VoidKey2Native, _VoidKey2Dart>('ef_derive_subkeys');
      computeBlindIndex = _lib.lookupFunction<_BlindNative, _BlindDart>('ef_compute_blind_index');
      computeFileBlindTag =
          _lib.lookupFunction<_FileBlindNative, _FileBlindDart>('ef_compute_file_blind_tag');
      encryptFile = _lib.lookupFunction<_EncryptFileNative, _EncryptFileDart>('ef_encrypt_file');
      decryptFile = _lib.lookupFunction<_DecryptFileNative, _DecryptFileDart>('ef_decrypt_file');
      secureDelete = _lib.lookupFunction<_SecureDeleteNative, _SecureDeleteDart>('ef_secure_delete');
      suggestChunkSize =
          _lib.lookupFunction<_SuggestChunkNative, _SuggestChunkDart>('ef_suggest_chunk_size');
      secureRandom = _lib.lookupFunction<_SecureRandomNative, _SecureRandomDart>('ef_secure_random');
      secureWipe = _lib.lookupFunction<_SecureWipeNative, _SecureWipeDart>('ef_secure_wipe');
      probeFile = _lib.lookupFunction<_ProbeNative, _ProbeDart>('ef_probe_file');
      streamServerStart =
          _lib.lookupFunction<_ServerStartNative, _ServerStartDart>('ef_stream_server_start');
      streamServerRegister =
          _lib.lookupFunction<_ServerRegisterNative, _ServerRegisterDart>('ef_stream_server_register');
      streamServerUnregister = _lib
          .lookupFunction<_ServerUnregisterNative, _ServerUnregisterDart>('ef_stream_server_unregister');
      streamServerStop =
          _lib.lookupFunction<_ServerStopNative, _ServerStopDart>('ef_stream_server_stop');
      streamServerClearKeys =
          _lib.lookupFunction<_ServerClearNative, _ServerClearDart>('ef_stream_server_clear_keys');
      encryptBegin = _lib.lookupFunction<_EncryptBeginNative, _EncryptBeginDart>('ef_encrypt_begin');
      encryptUpdate = _lib.lookupFunction<_EncryptUpdateNative, _EncryptUpdateDart>('ef_encrypt_update');
      encryptFinish = _lib.lookupFunction<_EncryptFinishNative, _EncryptFinishDart>('ef_encrypt_finish');
      encryptAbort = _lib.lookupFunction<_EncryptAbortNative, _EncryptAbortDart>('ef_encrypt_abort');
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
