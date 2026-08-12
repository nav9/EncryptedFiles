import 'dart:async';

import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/ui/widgets/lock_all_button.dart';
import 'package:flutter/material.dart';

/// Image viewer with optional slideshow mode.
///
/// Streams images from the native localhost server so decrypted bytes never
/// land on disk. Supports all image types that Flutter can render, including
/// WebP, PNG, JPEG, GIF, and BMP.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.slideshowMode = false,
    this.slideshowIntervalSec = 6,
  });

  final List<EncryptedFileRef> images;
  final int initialIndex;
  final bool slideshowMode;
  final int slideshowIntervalSec;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late PageController _pageCtrl;
  int _currentIndex = 0;
  Timer? _slideshowTimer;
  bool _slideshowRunning = false;

  // Map from fileRef.id to registered URL
  final Map<String, String> _urlCache = {};
  final Map<String, String> _tokenCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _currentIndex);
    if (widget.slideshowMode) {
      _startSlideshow();
    }
  }

  void _startSlideshow() {
    _slideshowRunning = true;
    _slideshowTimer = Timer.periodic(
      Duration(seconds: widget.slideshowIntervalSec),
      (_) {
        if (!mounted) return;
        if (_currentIndex < widget.images.length - 1) {
          _pageCtrl.nextPage(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
          );
        } else {
          _pageCtrl.animateToPage(
            0,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
          );
        }
      },
    );
  }

  void _stopSlideshow() {
    _slideshowTimer?.cancel();
    _slideshowTimer = null;
    _slideshowRunning = false;
  }

  Future<String?> _getUrl(EncryptedFileRef ref) async {
    if (_urlCache.containsKey(ref.id)) return _urlCache[ref.id];
    try {
      final reg = await AppDi.streamServer.register(ref.diskPath);
      _urlCache[ref.id] = reg.url;
      _tokenCache[ref.id] = reg.token;
      return reg.url;
    } catch (e) {
      await AppDi.logs.error('ImageViewer', 'Register failed for ${ref.id}: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _stopSlideshow();
    // Unregister all registered tokens.
    for (final token in _tokenCache.values) {
      try {
        AppDi.streamServer.unregister(token);
      } catch (_) {}
    }
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = widget.images[_currentIndex];

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
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
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
          // Slideshow toggle
          IconButton(
            icon: Icon(
              _slideshowRunning ? Icons.pause_presentation : Icons.slideshow,
              color: Colors.white,
            ),
            tooltip: _slideshowRunning ? 'Pause slideshow' : 'Start slideshow',
            onPressed: () {
              setState(() {
                if (_slideshowRunning) {
                  _stopSlideshow();
                } else {
                  _startSlideshow();
                }
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Page view of images
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              final imgRef = widget.images[i];
              return FutureBuilder<String?>(
                future: _getUrl(imgRef),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  final url = snap.data;
                  if (url == null) {
                    return Center(
                      child: Text(
                        'Failed to load image',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    );
                  }
                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Center(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, e, __) => Center(
                          child: Text(
                            'Image load error: $e',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                                color: Colors.white),
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // Bottom navigation overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.black54,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: () {
                      final target = _currentIndex == 0
                          ? widget.images.length - 1
                          : _currentIndex - 1;
                      _pageCtrl.animateToPage(
                        target,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                  Text(
                    '${_currentIndex + 1} / ${widget.images.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.chevron_right, color: Colors.white),
                    onPressed: () {
                      final target = _currentIndex == widget.images.length - 1
                          ? 0
                          : _currentIndex + 1;
                      _pageCtrl.animateToPage(
                        target,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
