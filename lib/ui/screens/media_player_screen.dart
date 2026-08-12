import 'dart:math';

import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/ui/widgets/lock_all_button.dart';
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
  double _speed = 1.0;
  bool _shuffle = false;
  bool _repeat = false;
  bool _showPlaylist = false;
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
      await ctrl.setPlaybackSpeed(_speed);
      await ctrl.setVolume(_isMuted ? 0 : _volume);
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
    if (widget.playlist.isEmpty) return;
    if (_shuffle) {
      _currentIndex = Random().nextInt(widget.playlist.length);
    } else {
      _currentIndex =
          _currentIndex == 0 ? widget.playlist.length - 1 : _currentIndex - 1;
    }
    await _loadCurrent();
  }

  Future<void> _next() async {
    if (widget.playlist.isEmpty) return;
    if (_repeat) {
      await _controller?.seekTo(Duration.zero);
      await _controller?.play();
      return;
    }
    if (_shuffle) {
      _currentIndex = Random().nextInt(widget.playlist.length);
    } else {
      _currentIndex =
          _currentIndex == widget.playlist.length - 1 ? 0 : _currentIndex + 1;
    }
    await _loadCurrent();
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
        leadingWidth: 96,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LockAllButton(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        title: Text(
          ref.realName ?? ref.fakeName,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(_showPlaylist ? Icons.queue_music : Icons.queue_music_outlined),
            tooltip: 'Playlist',
            onPressed: () => setState(() => _showPlaylist = !_showPlaylist),
          ),
        ],
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
                if (_showPlaylist)
                  SizedBox(
                    height: 96,
                    child: ListView.builder(
                      itemCount: widget.playlist.length,
                      itemBuilder: (_, i) {
                        final item = widget.playlist[i];
                        return ListTile(
                          dense: true,
                          selected: i == _currentIndex,
                          textColor: Colors.white70,
                          selectedColor: Colors.white,
                          title: Text(
                            item.realName ?? item.fakeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () async {
                            _currentIndex = i;
                            await _loadCurrent();
                          },
                        );
                      },
                    ),
                  ),
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
                      onPressed: widget.playlist.length > 1 ? _previous : null,
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
                      onPressed: widget.playlist.length > 1 || _repeat ? _next : null,
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        _shuffle ? Icons.shuffle_on_outlined : Icons.shuffle,
                        color: _shuffle ? theme.colorScheme.primary : Colors.white70,
                      ),
                      tooltip: 'Shuffle',
                      onPressed: () => setState(() => _shuffle = !_shuffle),
                    ),
                    IconButton(
                      icon: Icon(
                        _repeat ? Icons.repeat_on_outlined : Icons.repeat,
                        color: _repeat ? theme.colorScheme.primary : Colors.white70,
                      ),
                      tooltip: 'Repeat current',
                      onPressed: () => setState(() => _repeat = !_repeat),
                    ),
                    TextButton(
                      onPressed: () async {
                        final next = _speed <= 0.75 ? 1.0 : _speed - 0.25;
                        setState(() => _speed = next);
                        await ctrl?.setPlaybackSpeed(next);
                      },
                      child: const Text('- Speed'),
                    ),
                    Text(
                      '${_speed.toStringAsFixed(2)}x',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: () async {
                        final next = _speed >= 2.0 ? 2.0 : _speed + 0.25;
                        setState(() => _speed = next);
                        await ctrl?.setPlaybackSpeed(next);
                      },
                      child: const Text('+ Speed'),
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
