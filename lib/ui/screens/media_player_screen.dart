import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/core/exceptions.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Playlist-based audio/video player.
///
/// Streams content from the native localhost HTTP server, so decrypted data
/// never touches disk. Supports play/pause, seek, volume, mute, and next/prev.
class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({
    super.key,
    required this.playlist,
    this.initialIndex = 0,
  });

  final List<EncryptedFileRef> playlist;
  final int initialIndex;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  VideoPlayerController? _controller;
  int _currentIndex = 0;
  bool _isMuted = false;
  double _volume = 1.0;
  bool _loading = true;
  String? _error;
  String? _currentToken;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final ref = widget.playlist[_currentIndex];

    setState(() {
      _loading = true;
      _error = null;
    });

    // Unregister previous token.
    _unregisterCurrent();
    await _controller?.dispose();
    _controller = null;

    try {
      final reg = await AppDi.streamServer.register(ref.diskPath);
      _currentToken = reg.token;
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(reg.url));
      await ctrl.initialize();
      ctrl.addListener(_onPlayerStateChanged);
      setState(() {
        _controller = ctrl;
        _loading = false;
      });
      await ctrl.play();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load: $e';
      });
      await AppDi.logs.error('MediaPlayer', 'Load failed for ${ref.id}: $e');
    }
  }

  void _onPlayerStateChanged() {
    if (_controller == null) return;
    // Auto-advance to next when current finishes.
    if (_controller!.value.position >= _controller!.value.duration &&
        _controller!.value.duration > Duration.zero &&
        !_controller!.value.isPlaying) {
      _next();
    }
    setState(() {});
  }

  void _unregisterCurrent() {
    final token = _currentToken;
    if (token != null) {
      try {
        AppDi.streamServer.unregister(token);
      } catch (_) {}
      _currentToken = null;
    }
  }

  Future<void> _previous() async {
    if (_currentIndex > 0) {
      _currentIndex--;
      await _loadCurrent();
    }
  }

  Future<void> _next() async {
    if (_currentIndex < widget.playlist.length - 1) {
      _currentIndex++;
      await _loadCurrent();
    }
  }

  @override
  void dispose() {
    _unregisterCurrent();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = widget.playlist[_currentIndex];
    final ctrl = _controller;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          ref.realName ?? ref.fakeName,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Video surface or audio art
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                      )
                    : ctrl != null && ctrl.value.isInitialized
                        ? AspectRatio(
                            aspectRatio: ctrl.value.size.width /
                                (ctrl.value.size.height == 0
                                    ? 1
                                    : ctrl.value.size.height),
                            child: VideoPlayer(ctrl),
                          )
                        : const Center(
                            child: Icon(Icons.music_note,
                                size: 96, color: Colors.white30),
                          ),
          ),

          // Controls panel
          Container(
            color: Colors.black87,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Column(
              children: [
                // Track title + index
                Text(
                  '${_currentIndex + 1} / ${widget.playlist.length}  ·  ${ref.realName ?? ref.fakeName}',
                  style:
                      theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Seek bar
                if (ctrl != null && ctrl.value.isInitialized)
                  VideoProgressIndicator(
                    ctrl,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: theme.colorScheme.primary,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                const SizedBox(height: 4),
                // Position / duration
                if (ctrl != null && ctrl.value.isInitialized)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(ctrl.value.position),
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11)),
                      Text(_fmt(ctrl.value.duration),
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                const SizedBox(height: 8),
                // Main buttons row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous,
                          color: Colors.white),
                      iconSize: 32,
                      onPressed: _currentIndex > 0 ? _previous : null,
                    ),
                    IconButton(
                      icon: Icon(
                        (ctrl?.value.isPlaying ?? false)
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: Colors.white,
                      ),
                      iconSize: 48,
                      onPressed: ctrl == null
                          ? null
                          : () {
                              ctrl.value.isPlaying
                                  ? ctrl.pause()
                                  : ctrl.play();
                            },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                      iconSize: 32,
                      onPressed:
                          _currentIndex < widget.playlist.length - 1
                              ? _next
                              : null,
                    ),
                  ],
                ),
                // Volume row
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() => _isMuted = !_isMuted);
                        ctrl?.setVolume(_isMuted ? 0 : _volume);
                      },
                    ),
                    Expanded(
                      child: Slider(
                        value: _isMuted ? 0 : _volume,
                        onChanged: (v) {
                          setState(() {
                            _volume = v;
                            _isMuted = v == 0;
                          });
                          ctrl?.setVolume(v);
                        },
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:$mm:$ss'
        : '$mm:$ss';
  }
}
