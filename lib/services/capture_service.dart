import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/crypto/crypto_service.dart';
import 'package:encrypted_files/crypto/password_vault.dart';
import 'package:encrypted_files/database/database_service.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/services/log_service.dart';
import 'package:encrypted_files/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// Handles camera photo, video, and microphone capture, encrypting directly
/// to the vault without leaving plaintext on disk.
class CaptureService {
  CaptureService({
    required this.crypto,
    required this.database,
    required this.passwordVault,
    required this.settings,
    required this.logs,
  });

  final CryptoService crypto;
  final DatabaseService database;
  final PasswordVault passwordVault;
  final SettingsService settings;
  final LogService logs;
  final _uuid = const Uuid();

  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  final AudioRecorder _audioRecorder = AudioRecorder();

  List<CameraDescription> get cameras => _cameras;
  CameraController? get cameraController => _cameraController;

  /// Initialize available cameras (call on app start or refresh).
  Future<void> refreshCameras() async {
    try {
      _cameras = await availableCameras();
    } catch (e) {
      _cameras = [];
      debugPrint('CaptureService.refreshCameras: $e');
    }
  }

  bool get hasCameras => _cameras.isNotEmpty;

  /// Open the camera at [index].
  Future<CameraController> openCamera({int index = 0}) async {
    if (_cameras.isEmpty) await refreshCameras();
    if (_cameras.isEmpty) throw EfIoException('No cameras available');

    await _cameraController?.dispose();
    final controller = CameraController(
      _cameras[index % _cameras.length],
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();
    _cameraController = controller;
    return controller;
  }

  Future<void> closeCamera() async {
    await _cameraController?.dispose();
    _cameraController = null;
  }

  /// Capture a single photo and encrypt it to [destDir].
  Future<EncryptedFileRef> capturePhoto({
    required String destDir,
    String? folderId,
  }) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw EfIoException('Camera not initialized');
    }

    final session = passwordVault.active;
    if (session == null) throw EfAuthException('No active password session');

    XFile? xFile;
    try {
      xFile = await controller.takePicture();
    } catch (e) {
      throw EfIoException('Failed to take picture', cause: e);
    }

    try {
      final bytes = await xFile.readAsBytes();
      final realName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = await _encryptBytes(
        bytes: bytes,
        realName: realName,
        mimeType: 'image/jpeg',
        destDir: destDir,
        session: session,
        folderId: folderId,
      );
      await logs.info('CaptureService', 'Photo captured → ${ref.fakeName}');
      return ref;
    } finally {
      try {
        await File(xFile.path).delete();
      } catch (_) {}
    }
  }

  /// Start audio recording (microphone → encrypted file on finish).
  Future<void> startAudioRecording({required String tempPath}) async {
    if (!await _audioRecorder.hasPermission()) {
      throw EfPermissionException('Microphone permission denied');
    }
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: tempPath,
    );
    await logs.debug('CaptureService', 'Audio recording started at $tempPath');
  }

  Future<bool> get isRecordingAudio => _audioRecorder.isRecording();

  /// Stop audio recording and encrypt the captured audio.
  Future<EncryptedFileRef?> stopAudioRecording({required String destDir}) async {
    return stopAudioRecordingToFolder(destDir: destDir);
  }

  Future<EncryptedFileRef?> stopAudioRecordingToFolder({
    required String destDir,
    String? folderId,
  }) async {
    final session = passwordVault.active;
    if (session == null) throw EfAuthException('No active password session');

    final path = await _audioRecorder.stop();
    if (path == null) return null;

    final tempFile = File(path);
    if (!await tempFile.exists()) return null;

    try {
      final realName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final ref = await _encryptFile(
        inputPath: path,
        realName: realName,
        mimeType: 'audio/mp4',
        fakeExtension: '.m4a',
        destDir: destDir,
        session: session,
        folderId: folderId,
      );

      await database.insertFileRef(ref);
      await logs.info('CaptureService', 'Audio captured -> ${ref.fakeName}');
      return ref;
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  Future<void> disposeAudio() => _audioRecorder.dispose();

  Future<void> startVideoRecording() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw EfIoException('Camera not initialized');
    }
    if (controller.value.isRecordingVideo) return;
    await controller.startVideoRecording();
    await logs.debug('CaptureService', 'Video recording started');
  }

  Future<bool> get isRecordingVideo async {
    final controller = _cameraController;
    return controller?.value.isRecordingVideo ?? false;
  }

  Future<EncryptedFileRef?> stopVideoRecording({
    required String destDir,
    String? folderId,
  }) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isRecordingVideo) return null;
    final session = passwordVault.active;
    if (session == null) throw EfAuthException('No active password session');

    final xFile = await controller.stopVideoRecording();
    final tempFile = File(xFile.path);
    if (!await tempFile.exists()) return null;

    try {
      final realName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final ref = await _encryptFile(
        inputPath: xFile.path,
        realName: realName,
        mimeType: 'video/mp4',
        fakeExtension: '.mp4',
        destDir: destDir,
        session: session,
        folderId: folderId,
      );
      await database.insertFileRef(ref);
      await logs.info('CaptureService', 'Video captured -> ${ref.fakeName}');
      return ref;
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  Future<EncryptedFileRef> _encryptBytes({
    required Uint8List bytes,
    required String realName,
    required String mimeType,
    required String destDir,
    required ActiveSession session,
    String? folderId,
  }) async {
    final fileId = _uuid.v4();
    final fileIdBytes = _uuidToBytes(fileId);
    final blindTag = crypto.fileBlindTag(session.keys, fileId: fileIdBytes);
    final storedFakeName = '${_uuid.v4()}.bin';
    final outputPath = p.join(destDir, storedFakeName);

    await Directory(destDir).create(recursive: true);
    await crypto.encryptStream(
      outputPath: outputPath,
      keys: session.keys,
      realName: realName,
      mimeType: mimeType,
      fileBlindTag: blindTag,
      chunkSize: settings.chunkBytes,
      plaintextSize: bytes.length,
      source: Stream.value(bytes),
    );

    final realNameEnc = Uint8List.fromList(passwordVault.encryptMetadata(realName));
    final mimeEnc = Uint8List.fromList(passwordVault.encryptMetadata(mimeType));
    final now = DateTime.now().toUtc();

    final ref = EncryptedFileRef(
      id: fileId,
      vaultId: session.vault.id,
      diskPath: outputPath,
      fakeName: storedFakeName,
      realNameEncrypted: realNameEnc,
      mimeEncrypted: mimeEnc,
      fileBlindTag: Uint8List.fromList(blindTag),
      sizeBytes: bytes.length,
      folderId: folderId,
      sortIndex: 0,
      createdAt: now,
      modifiedAt: now,
      realName: realName,
      mimeType: mimeType,
    );

    await database.insertFileRef(ref);
    return ref;
  }

  Future<EncryptedFileRef> _encryptFile({
    required String inputPath,
    required String realName,
    required String mimeType,
    required String fakeExtension,
    required String destDir,
    required ActiveSession session,
    String? folderId,
  }) async {
    final fileId = _uuid.v4();
    final fileIdBytes = _uuidToBytes(fileId);
    final blindTag = crypto.fileBlindTag(session.keys, fileId: fileIdBytes);
    final storedFakeName = '${_uuid.v4()}$fakeExtension';
    final outputPath = p.join(destDir, storedFakeName);

    await Directory(destDir).create(recursive: true);
    await crypto.encryptFile(
      inputPath: inputPath,
      outputPath: outputPath,
      keys: session.keys,
      realName: realName,
      mimeType: mimeType,
      fileBlindTag: blindTag,
      chunkSize: settings.chunkBytes,
    );

    final sizeBytes = await File(inputPath).length();
    final now = DateTime.now().toUtc();
    return EncryptedFileRef(
      id: fileId,
      vaultId: session.vault.id,
      diskPath: outputPath,
      fakeName: storedFakeName,
      realNameEncrypted: Uint8List.fromList(passwordVault.encryptMetadata(realName)),
      mimeEncrypted: Uint8List.fromList(passwordVault.encryptMetadata(mimeType)),
      fileBlindTag: Uint8List.fromList(blindTag),
      sizeBytes: sizeBytes,
      folderId: folderId,
      sortIndex: 0,
      createdAt: now,
      modifiedAt: now,
      realName: realName,
      mimeType: mimeType,
    );
  }

  Uint8List _uuidToBytes(String uuid) {
    final hex = uuid.replaceAll('-', '');
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
