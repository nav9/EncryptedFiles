import 'dart:ffi';

import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/crypto/native_bindings.dart';
import 'package:encrypted_files/crypto/password_vault.dart';
import 'package:encrypted_files/services/settings_service.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

class StreamRegistration {
  StreamRegistration({required this.token, required this.url});
  final String token;
  final String url;
}

/// Dart-side wrapper around the native loopback HTTP stream server.
class StreamServerService {
  StreamServerService(this._bindings, this._settings);

  final NativeBindings _bindings;
  final SettingsService _settings;

  Pointer<Void>? _server;
  int _port = 0;
  final Map<String, String> _tokenToUrl = {};

  bool get isRunning => _server != null && _server != nullptr;
  int get port => _port;

  /// Start the streaming server with the current session's enc key.
  void start(ActiveSession session) {
    if (isRunning) stop();

    final keyPtr = _bindings.bytesToNative(session.keys.enc.bytes);
    final portPtr = malloc<Int32>();
    try {
      final chunk = _settings.streamChunkOverride;
      final srv = _bindings.streamServerStart(keyPtr, chunk, portPtr);
      if (srv == nullptr) {
        throw EfCryptoException('Failed to start stream server');
      }
      _server = srv;
      _port = portPtr.value;
      debugPrint('StreamServerService: started on port $_port');
    } finally {
      _bindings.wipeAndFree(keyPtr, 32);
      malloc.free(portPtr);
    }
  }

  /// Register an encrypted file path, returning a token and localhost URL.
  Future<StreamRegistration> register(String encryptedPath) async {
    final srv = _server;
    if (srv == null || srv == nullptr) {
      throw EfCryptoException('Stream server not running');
    }

    final pathPtr = encryptedPath.toNativeUtf8();
    // token: 64 hex chars + null
    final tokenPtr = malloc<Uint8>(65).cast<Utf8>();
    // url: e.g. http://127.0.0.1:59123/d/<64hexchars> ≈ 100 chars
    final urlPtr = malloc<Uint8>(256).cast<Utf8>();
    try {
      final rc = _bindings.streamServerRegister(
        srv,
        pathPtr,
        tokenPtr,
        65,
        urlPtr,
        256,
      );
      if (rc != 0) {
        throw EfCryptoException('Stream server register failed', code: rc);
      }
      final token = tokenPtr.toDartString();
      final url = urlPtr.toDartString();
      _tokenToUrl[token] = url;
      return StreamRegistration(token: token, url: url);
    } finally {
      malloc.free(pathPtr);
      malloc.free(tokenPtr);
      malloc.free(urlPtr);
    }
  }

  /// Unregister a previously registered token.
  void unregister(String token) {
    final srv = _server;
    if (srv == null || srv == nullptr) return;
    final tokenPtr = token.toNativeUtf8();
    try {
      _bindings.streamServerUnregister(srv, tokenPtr);
      _tokenToUrl.remove(token);
    } finally {
      malloc.free(tokenPtr);
    }
  }

  String? tokenToUrl(String token) => _tokenToUrl[token];

  /// Wipe the enc key from the server (called when clearing active password).
  void clearKeys() {
    final srv = _server;
    if (srv == null || srv == nullptr) return;
    _bindings.streamServerClearKeys(srv);
    _tokenToUrl.clear();
  }

  /// Stop and destroy the server.
  void stop() {
    final srv = _server;
    if (srv == null || srv == nullptr) return;
    _bindings.streamServerStop(srv);
    _server = null;
    _port = 0;
    _tokenToUrl.clear();
    debugPrint('StreamServerService: stopped');
  }
}
