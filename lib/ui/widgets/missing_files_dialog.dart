import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

/// Shows when vault files cannot be found on disk after load.
///
/// Allows the user to:
///   1. Remove the missing file references from the database.
///   2. Search a chosen folder for the files (auto-updates DB paths on match).
class MissingFilesDialog extends StatefulWidget {
  const MissingFilesDialog({super.key, required this.missingRefs});

  final List<EncryptedFileRef> missingRefs;

  @override
  State<MissingFilesDialog> createState() => _MissingFilesDialogState();
}

class _MissingFilesDialogState extends State<MissingFilesDialog> {
  final Set<String> _selectedIds = {};
  bool _searching = false;
  String _searchStatus = '';

  // Report from last search: id -> found path or null
  final Map<String, String?> _searchResults = {};

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.missingRefs.map((r) => r.id));
  }

  Future<void> _searchForFiles() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || !mounted) return;

    setState(() {
      _searching = true;
      _searchStatus = 'Searching…';
      _searchResults.clear();
    });

    final state = context.read<AppState>();

    try {
      final result = await AppDi.searchService.searchDirectory(
        rootDir: dir,
        onFile: (path) {
          if (mounted) {
            setState(() => _searchStatus = 'Scanning: $path');
          }
        },
      );

      // Build a map of fakeName -> found diskPath for quick look-up.
      final foundMap = <String, String>{};
      for (final found in result.found) {
        foundMap[p.basename(found)] = found;
      }

      int updated = 0;
      for (final ref in widget.missingRefs) {
        final newPath = foundMap[ref.fakeName];
        if (newPath != null) {
          // Update DB and in-memory state.
          final updated0 = ref.copyWith(diskPath: newPath, missingOnDisk: false);
          await AppDi.database.updateFileRef(updated0);
          state.updateRef(updated0);
          _searchResults[ref.id] = newPath;
          updated++;
        } else {
          _searchResults[ref.id] = null;
        }
      }

      await AppDi.logs.info(
        'MissingFilesDialog',
        'Search complete: $updated/${widget.missingRefs.length} files found',
      );

      setState(() {
        _searching = false;
        _searchStatus = '$updated of ${widget.missingRefs.length} file(s) located.';
      });
    } catch (e) {
      setState(() {
        _searching = false;
        _searchStatus = 'Search failed: $e';
      });
    }
  }

  Future<void> _removeSelected() async {
    final state = context.read<AppState>();
    for (final id in _selectedIds) {
      try {
        await AppDi.database.deleteFileRef(id);
        state.removeRef(id);
        await AppDi.logs.info('MissingFilesDialog', 'Removed missing ref $id');
      } catch (e) {
        await AppDi.logs.error('MissingFilesDialog', 'Failed to remove $id: $e');
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.amber),
          const SizedBox(width: 8),
          const Expanded(child: Text('Missing Files Detected')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.missingRefs.length} file(s) in your vault could not be found on disk.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // File list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.missingRefs.length,
                itemBuilder: (_, i) {
                  final ref = widget.missingRefs[i];
                  final foundPath = _searchResults[ref.id];
                  final wasSearched = _searchResults.containsKey(ref.id);
                  return CheckboxListTile(
                    dense: true,
                    value: _selectedIds.contains(ref.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedIds.add(ref.id);
                      } else {
                        _selectedIds.remove(ref.id);
                      }
                    }),
                    title: Text(
                      ref.realName ?? ref.fakeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    subtitle: wasSearched
                        ? Text(
                            foundPath != null
                                ? '✓ Found: $foundPath'
                                : '✗ Not found in search folder',
                            style: TextStyle(
                              fontSize: 10,
                              color: foundPath != null
                                  ? Colors.green
                                  : theme.colorScheme.error,
                            ),
                          )
                        : Text(
                            ref.diskPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                  );
                },
              ),
            ),
            if (_searching) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_searchStatus.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_searchStatus,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Dismiss'),
        ),
        TextButton(
          onPressed: _searching ? null : _searchForFiles,
          child: const Text('Search Folder…'),
        ),
        if (_selectedIds.isNotEmpty)
          FilledButton.tonal(
            onPressed: _searching ? null : _removeSelected,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            child: Text('Remove ${_selectedIds.length} Selected'),
          ),
      ],
    );
  }
}
