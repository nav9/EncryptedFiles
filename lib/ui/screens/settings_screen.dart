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
  int _suggestedChunk = AppConstants.defaultChunkBytes;

  @override
  void initState() {
    super.initState();
    _chunkBytes = AppDi.settings.chunkBytes;
    _autoChunk = AppDi.settings.autoSuggestChunk;
    _isDark = AppDi.settings.isDarkTheme;
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
        title: const Text('Settings'),
        actions: const [LockAllButton()],
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
                value: AppConstants.allowedChunkSizes.contains(_chunkBytes)
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
              value: AppConstants.allowedChunkSizes
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
