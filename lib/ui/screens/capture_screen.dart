import 'package:camera/camera.dart';
import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:encrypted_files/ui/widgets/lock_all_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum CaptureMode { camera, microphone }

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.mode,
    this.folderId,
  });

  final CaptureMode mode;
  final String? folderId;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _camera;
  bool _loading = true;
  bool _recordingVideo = false;
  bool _recordingAudio = false;
  String? _error;
  int _cameraIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.mode == CaptureMode.camera ? _initCamera() : _initAudio();
  }

  Future<void> _initCamera() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppDi.captureService.refreshCameras();
      final controller = await AppDi.captureService.openCamera(index: _cameraIndex);
      if (!mounted) return;
      setState(() {
        _camera = controller;
        _loading = false;
      });
      if (AppDi.settings.cameraAutoRecord) {
        await _startVideo();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Camera unavailable: $e';
        });
      }
    }
  }

  Future<void> _initAudio() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tempPath =
          '${AppDi.appRoot}/audio_capture_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await AppDi.captureService.startAudioRecording(tempPath: tempPath);
      if (mounted) {
        setState(() {
          _loading = false;
          _recordingAudio = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Microphone unavailable: $e';
        });
      }
    }
  }

  Future<void> _startVideo() async {
    try {
      await AppDi.captureService.startVideoRecording();
      if (mounted) setState(() => _recordingVideo = true);
    } catch (e) {
      _showError('Could not start video: $e');
    }
  }

  Future<void> _stopVideo() async {
    try {
      setState(() => _loading = true);
      final ref = await AppDi.captureService.stopVideoRecording(
        destDir: AppDi.appRoot,
        folderId: widget.folderId,
      );
      if (ref != null && mounted) {
        context.read<AppState>().addRef(ref);
        _showSaved(ref);
      }
    } catch (e) {
      _showError('Could not save video: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _recordingVideo = false;
        });
      }
    }
  }

  Future<void> _capturePhoto() async {
    try {
      setState(() => _loading = true);
      final ref = await AppDi.captureService.capturePhoto(
        destDir: AppDi.appRoot,
        folderId: widget.folderId,
      );
      if (mounted) {
        context.read<AppState>().addRef(ref);
        _showSaved(ref);
      }
    } catch (e) {
      _showError('Could not capture photo: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stopAudio() async {
    try {
      setState(() => _loading = true);
      final ref = await AppDi.captureService.stopAudioRecordingToFolder(
        destDir: AppDi.appRoot,
        folderId: widget.folderId,
      );
      if (ref != null && mounted) {
        context.read<AppState>().addRef(ref);
        _showSaved(ref);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Could not save audio: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _recordingAudio = false;
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    final cameras = AppDi.captureService.cameras;
    if (cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % cameras.length;
    await _initCamera();
  }

  Future<void> _close() async {
    if (_recordingVideo) {
      await _stopVideo();
    }
    if (_recordingAudio) {
      await _stopAudio();
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleFlash() async {
    final camera = _camera;
    if (camera == null) return;
    final next = camera.value.flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await camera.setFlashMode(next);
      if (mounted) setState(() {});
    } catch (e) {
      _showError('Flash unavailable: $e');
    }
  }

  void _showSaved(EncryptedFileRef ref) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${ref.realName ?? ref.fakeName}')),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    AppDi.captureService.closeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leadingWidth: 96,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LockAllButton(),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: _close,
            ),
          ],
        ),
        title: Text(widget.mode == CaptureMode.camera ? 'Camera' : 'Microphone'),
        actions: [
          if (widget.mode == CaptureMode.camera)
            IconButton(
              icon: const Icon(Icons.cameraswitch_outlined),
              tooltip: 'Switch camera',
              onPressed: AppDi.captureService.cameras.length > 1 ? _switchCamera : null,
            ),
          if (widget.mode == CaptureMode.camera)
            IconButton(
              icon: Icon(
                camera?.value.flashMode == FlashMode.torch
                    ? Icons.flash_on
                    : Icons.flash_off,
              ),
              tooltip: 'Flash',
              onPressed: _toggleFlash,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              : widget.mode == CaptureMode.camera
                  ? _buildCamera(camera)
                  : _buildAudio(),
    );
  }

  Widget _buildCamera(CameraController? camera) {
    if (camera == null || !camera.value.isInitialized) {
      return const Center(
        child: Text('No camera available', style: TextStyle(color: Colors.white70)),
      );
    }

    return Stack(
      children: [
        Center(child: CameraPreview(camera)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.photo_camera_outlined),
                tooltip: 'Take photo',
                iconSize: 32,
                onPressed: _recordingVideo ? null : _capturePhoto,
              ),
              const SizedBox(width: 18),
              IconButton.filled(
                icon: Icon(_recordingVideo ? Icons.stop : Icons.fiber_manual_record),
                tooltip: _recordingVideo ? 'Stop and save video' : 'Record video',
                color: _recordingVideo ? Colors.white : Colors.red,
                iconSize: 40,
                onPressed: _recordingVideo ? _stopVideo : _startVideo,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAudio() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _recordingAudio ? Icons.mic : Icons.mic_none,
            color: _recordingAudio ? Colors.red : Colors.white54,
            size: 80,
          ),
          const SizedBox(height: 16),
          Text(
            _recordingAudio ? 'Recording audio' : 'Audio stopped',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.stop),
            onPressed: _recordingAudio ? _stopAudio : () => Navigator.pop(context),
            label: Text(_recordingAudio ? 'Stop and Save' : 'Close'),
          ),
        ],
      ),
    );
  }
}
