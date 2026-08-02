import 'dart:io';

import 'package:encrypted_files/core/exceptions.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Abstracts platform permission requests.
class PermissionService {
  /// Request storage access (external files).
  Future<bool> requestStorage() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    try {
      if (await Permission.storage.isGranted) return true;
      // Android 13+: use media permissions instead.
      if (Platform.isAndroid) {
        final sdk = await _androidSdkVersion();
        if (sdk >= 33) {
          final results = await [
            Permission.photos,
            Permission.videos,
            Permission.audio,
          ].request();
          return results.values.any((s) => s.isGranted);
        }
        if (sdk >= 30) {
          final status = await Permission.manageExternalStorage.request();
          if (status.isGranted) return true;
        }
      }
      final status = await Permission.storage.request();
      return status.isGranted;
    } catch (e, st) {
      debugPrint('PermissionService.requestStorage: $e\n$st');
      throw EfPermissionException('Storage permission request failed', cause: e);
    }
  }

  /// Request camera access.
  Future<bool> requestCamera() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    try {
      if (await Permission.camera.isGranted) return true;
      final status = await Permission.camera.request();
      return status.isGranted;
    } catch (e, st) {
      debugPrint('PermissionService.requestCamera: $e\n$st');
      throw EfPermissionException('Camera permission request failed', cause: e);
    }
  }

  /// Request microphone access.
  Future<bool> requestMicrophone() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    try {
      if (await Permission.microphone.isGranted) return true;
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (e, st) {
      debugPrint('PermissionService.requestMicrophone: $e\n$st');
      throw EfPermissionException('Microphone permission request failed', cause: e);
    }
  }

  Future<bool> hasStorage() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    try {
      return await Permission.storage.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<int> _androidSdkVersion() async {
    if (!Platform.isAndroid) return 0;
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(result.stdout.toString().trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
