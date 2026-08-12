import 'dart:io';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:encrypted_files/ui/widgets/lock_all_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _chunkBytes;
  late bool _autoChunk;
  late bool _isDark;
  late int _slideshowSeconds;
  late bool _cameraAutoRecord;
  int _suggestedChunk = AppConstants.defaultChunkBytes;

  @override
  void initState() {
    super.initState();
    _chunkBytes = AppDi.settings.chunkBytes;
    _autoChunk = AppDi.settings.autoSuggestChunk;
    _isDark = AppDi.settings.isDarkTheme;
    _slideshowSeconds = AppDi.settings.slideshowSeconds;
    _cameraAutoRecord = AppDi.settings.cameraAutoRecord;
    _computeSuggested();
  }

  void _computeSuggested() {
    try {
      // Query available RAM in KiB (Linux/Android approximation).
      int ramKib = 0;
      if (Platform.isLinux) {
        try {
          final memInfo = File('/proc/meminfo').readAsStringSync();
          final match = RegExp(r'MemAvailable:\s+(\d+)').firstMatch(memInfo);
          ramKib = int.tryParse(match?.group(1) ?? '0') ?? 0;
        } catch (_) {}
      }
      final suggested = AppDi.crypto.suggestChunkSize(ramKib);
      setState(() => _suggestedChunk = suggested);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
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
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme
          _Section('Appearance'),
          SwitchListTile(
            title: const Text('Dark theme'),
            subtitle: const Text('Deep blue dark mode (default)'),
            value: _isDark,
            onChanged: (v) async {
              setState(() => _isDark = v);
              await state.setDarkTheme(v);
            },
          ),

          const Divider(),
          _Section('Vault Screen'),
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: const Text('Slideshow interval'),
            subtitle: Text('$_slideshowSeconds seconds per image'),
            trailing: SizedBox(
              width: 96,
              child: DropdownButtonFormField<int>(
                initialValue: _slideshowSeconds,
                items: const [2, 4, 6, 8, 10, 15, 30]
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text('${s}s'),
                      ),
                    )
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _slideshowSeconds = v);
                  await AppDi.settings.setSlideshowSeconds(v);
                },
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.videocam_outlined),
            title: const Text('Start video recording immediately'),
            subtitle: const Text('Applies when opening Camera from a vault'),
            value: _cameraAutoRecord,
            onChanged: (v) async {
              setState(() => _cameraAutoRecord = v);
              await AppDi.settings.setCameraAutoRecord(v);
            },
          ),

          const Divider(),
          _Section('Navigation Bar'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('Drag to reorder icons on the main screen:'),
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIndex, newIndex) async {
              setState(() {
                if (newIndex > oldIndex) {
                  newIndex -= 1;
                }
                final item = AppDi.settings.navBarIcons.removeAt(oldIndex);
                AppDi.settings.navBarIcons.insert(newIndex, item);
              });
              await AppDi.settings.setNavBarIcons(AppDi.settings.navBarIcons);
              // Notify app state about change if needed, but setState rebuilds.
            },
            children: AppDi.settings.navBarIcons.map((iconId) {
              IconData iconData;
              String title;
              switch (iconId) {
                case 'import':
                  iconData = Icons.file_upload_outlined;
                  title = 'Import';
                  break;
                case 'camera':
                  iconData = Icons.camera_alt_outlined;
                  title = 'Camera';
                  break;
                case 'mic':
                  iconData = Icons.mic_none;
                  title = 'Microphone';
                  break;
                default:
                  iconData = Icons.device_unknown;
                  title = iconId;
              }
              return ListTile(
                key: ValueKey(iconId),
                leading: Icon(iconData),
                title: Text(title),
                trailing: const Icon(Icons.drag_handle),
              );
            }).toList(),
          ),

          const Divider(),
          _Section('Encryption Chunk Size'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Suggested for this device: ${_fmtChunk(_suggestedChunk)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          SwitchListTile(
            title: const Text('Auto-suggest chunk size'),
            subtitle: const Text('Use device RAM to determine optimal size'),
            value: _autoChunk,
            onChanged: (v) async {
              setState(() => _autoChunk = v);
              await AppDi.settings.setAutoSuggestChunk(v);
              if (v) {
                setState(() => _chunkBytes = _suggestedChunk);
                await AppDi.settings.setChunkBytes(_suggestedChunk);
              }
            },
          ),
          if (!_autoChunk)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Chunk size'),
                initialValue: AppConstants.allowedChunkSizes.contains(_chunkBytes)
                    ? _chunkBytes
                    : AppConstants.defaultChunkBytes,
                items: AppConstants.allowedChunkSizes.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(_fmtChunk(s)),
                  );
                }).toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _chunkBytes = v);
                  await AppDi.settings.setChunkBytes(v);
                },
              ),
            ),

          const Divider(),
          _Section('Stream Server'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                  labelText: 'Streaming chunk override (0 = file header)'),
              initialValue: AppConstants.allowedChunkSizes
                      .contains(AppDi.settings.streamChunkOverride)
                  ? AppDi.settings.streamChunkOverride
                  : 0,
              items: [
                const DropdownMenuItem(value: 0, child: Text('Auto (file header)')),
                ...AppConstants.allowedChunkSizes.map((s) {
                  return DropdownMenuItem(value: s, child: Text(_fmtChunk(s)));
                }),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await AppDi.settings.setStreamChunkOverride(v);
              },
            ),
          ),

          const Divider(),
          _Section('Logs'),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear all logs'),
            onTap: () async {
              await AppDi.logs.clear();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logs cleared')));
              }
            },
          ),
        ],
      ),
    );
  }

  String _fmtChunk(int bytes) {
    if (bytes < 1024 * 1024) return '${bytes ~/ 1024} KB';
    return '${bytes ~/ (1024 * 1024)} MB';
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
