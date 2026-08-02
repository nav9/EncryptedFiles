import 'dart:io';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/database/models/virtual_folder.dart';
import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:encrypted_files/ui/screens/about_screen.dart';
import 'package:encrypted_files/ui/screens/help_screen.dart';
import 'package:encrypted_files/ui/screens/logs_screen.dart';
import 'package:encrypted_files/ui/screens/settings_screen.dart';
import 'package:encrypted_files/ui/widgets/file_actions_sheet.dart';
import 'package:encrypted_files/ui/widgets/file_card.dart';
import 'package:encrypted_files/ui/widgets/folder_card.dart';
import 'package:encrypted_files/ui/widgets/lock_all_button.dart';
import 'package:encrypted_files/ui/widgets/missing_files_dialog.dart';
import 'package:encrypted_files/ui/widgets/password_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Set<String> _selectedIds = {};
  bool _selectMode = false;
  String? _currentFolderId; // null = root
  SortMode _sortMode = SortMode.manual;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final isAndroid = Platform.isAndroid;

    return Scaffold(
      drawer: _buildDrawer(context, theme),
      appBar: _buildAppBar(context, state, theme, isAndroid),
      body: _buildBody(context, state, theme),
      bottomNavigationBar: _selectedIds.isNotEmpty
          ? _buildSelectionBar(context, state, theme)
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    AppState state,
    ThemeData theme,
    bool isAndroid,
  ) {
    return AppBar(
      leading: Builder(builder: (ctx) {
        return IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Menu',
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        );
      }),
      title: Row(
        children: [
          const Icon(Icons.lock_outline, size: 18),
          const SizedBox(width: 6),
          Text(
            _currentFolderId != null
                ? _folderName(state, _currentFolderId!)
                : AppConstants.appName,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        // Emergency lock-all button (red shield)
        const LockAllButton(),
        // Password button
        IconButton(
          icon: Icon(
            state.hasSession ? Icons.lock_open : Icons.lock_outline,
            color: state.hasSession
                ? Colors.greenAccent
                : theme.colorScheme.onSurface,
          ),
          tooltip: state.hasSession ? 'Change/Clear Password' : 'Enter Password',
          onPressed: () => _showPasswordDialog(context, state),
        ),
        // Import (load) button
        if (state.hasSession)
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import File(s)',
            onPressed: () => _importFiles(context, state),
          ),
        // Camera button (Android & desktop)
        if (state.hasSession && (isAndroid || !Platform.isIOS))
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Camera Capture',
            onPressed: () => _openCamera(context, state),
          ),
        // Mic button
        if (state.hasSession && (isAndroid || !Platform.isIOS))
          IconButton(
            icon: const Icon(Icons.mic_none),
            tooltip: 'Record Audio',
            onPressed: () => _startAudioRecording(context, state),
          ),
        // Sort / overflow menu
        if (state.hasSession)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (v) => _onOverflowMenu(context, state, v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new_folder', child: Text('New Folder')),
              const PopupMenuItem(value: 'download', child: Text('Download URL')),
              const PopupMenuItem(value: 'search', child: Text('Search Disk')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'sort_name_asc', child: Text('Sort A→Z')),
              const PopupMenuItem(value: 'sort_name_desc', child: Text('Sort Z→A')),
              const PopupMenuItem(value: 'sort_created_desc', child: Text('Sort Newest')),
              const PopupMenuItem(value: 'sort_modified_desc', child: Text('Sort Modified')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'clear_password', child: Text('Clear Password')),
            ],
          ),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context, ThemeData theme) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: theme.colorScheme.surface),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.security, size: 36, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(AppConstants.appName,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text('Secure vault', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HelpScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title: const Text('Logs'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LogsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AboutScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppState state, ThemeData theme) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!state.hasSession) {
      return _buildEmptyState(context, theme);
    }

    final folders = state.subFolders(_currentFolderId);
    final files = state.filesInFolder(_currentFolderId);

    if (folders.isEmpty && files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              _currentFolderId != null ? 'Empty folder' : 'No files present',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            Text(
              'Import files using the ↑ button above',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: state.loadVaultContents,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          // "Up" folder navigation
          if (_currentFolderId != null)
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('..  (back)'),
              onTap: () => setState(() => _currentFolderId = null),
            ),
          // Folders first
          ...folders.map((f) => FolderCard(
                folder: f,
                isSelected: _selectedIds.contains(f.id),
                onTap: () {
                  if (_selectMode) {
                    _toggleSelect(f.id);
                  } else {
                    setState(() => _currentFolderId = f.id);
                  }
                },
                onLongPress: () => _toggleSelect(f.id),
                onCheckChanged: (_) => _toggleSelect(f.id),
              )),
          // Files
          ...files.map((ref) => FileCard(
                fileRef: ref,
                isSelected: _selectedIds.contains(ref.id),
                onTap: () {
                  if (_selectMode) {
                    _toggleSelect(ref.id);
                  } else {
                    _openFile(context, state, ref);
                  }
                },
                onLongPress: () => _openFileActions(context, state, ref),
                onCheckChanged: (_) => _toggleSelect(ref.id),
              )),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 80, color: theme.colorScheme.primary.withAlpha(120)),
            const SizedBox(height: 24),
            Text('No files present',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              'Tap the 🔒 icon in the toolbar to enter a password and unlock your vault.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.lock_open),
              label: const Text('Enter Password'),
              onPressed: () =>
                  _showPasswordDialog(context, AppDi.appState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar(
      BuildContext context, AppState state, ThemeData theme) {
    final selectedRefs = state.fileRefs
        .where((f) => _selectedIds.contains(f.id))
        .toList();
    final selectedFolders = state.folders
        .where((f) => _selectedIds.contains(f.id))
        .toList();

    // Determine common media kind
    final kinds = selectedRefs.map((f) => f.mediaKind).toSet();
    final canPlay = kinds.isNotEmpty &&
        (kinds.every((k) => k == MediaKind.audio || k == MediaKind.video));
    final canView =
        kinds.length == 1 && kinds.first == MediaKind.image;

    return BottomAppBar(
      child: Row(
        children: [
          Text('${_selectedIds.length} selected',
              style: theme.textTheme.bodySmall),
          const Spacer(),
          if (canView)
            IconButton(
              icon: const Icon(Icons.slideshow),
              tooltip: 'Slideshow',
              onPressed: () => _viewSlideshow(context, selectedRefs),
            ),
          if (canPlay)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Play',
              onPressed: () => _playFiles(context, selectedRefs),
            ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Export Unencrypted',
            onPressed: () =>
                _exportSelected(context, state, selectedRefs, selectedFolders),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () =>
                _deleteSelected(context, state, selectedRefs, selectedFolders),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _clearSelection,
          ),
        ],
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      _selectMode = _selectedIds.isNotEmpty;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectMode = false;
    });
  }

  String _folderName(AppState state, String folderId) {
    final f = state.folders.where((f) => f.id == folderId).firstOrNull;
    return f?.name ?? 'Folder';
  }

  Future<void> _showPasswordDialog(
      BuildContext context, AppState state) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PasswordDialog(),
    );
    if (result == true && mounted) {
      await state.loadVaultContents();
      // Check for missing files and show resolution dialog.
      if (mounted) {
        final missing = state.fileRefs.where((r) => r.missingOnDisk).toList();
        if (missing.isNotEmpty) {
          await showDialog(
            context: context,
            barrierDismissible: true,
            builder: (_) => MissingFilesDialog(missingRefs: missing),
          );
        }
      }
    }
  }

  Future<void> _importFiles(BuildContext context, AppState state) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    state.setStatus('Importing ${result.files.length} file(s)...');
    try {
      for (final file in result.files) {
        if (file.path == null) continue;
        final ref = await AppDi.importService.importFile(
          sourcePath: file.path!,
          destDir: AppDi.appRoot,
          folderId: _currentFolderId,
        );
        state.addRef(ref);
      }
      state.setStatus('Import complete');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      state.setStatus(null);
    }
  }

  Future<void> _openCamera(BuildContext context, AppState state) async {
    final granted = await AppDi.permissions.requestCamera();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission denied')));
      return;
    }
    // Push camera screen (placeholder — full implementation in camera_screen.dart)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera screen coming soon')));
    }
  }

  Future<void> _startAudioRecording(BuildContext context, AppState state) async {
    final granted = await AppDi.permissions.requestMicrophone();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')));
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio recording coming soon')));
    }
  }

  Future<void> _openFile(
      BuildContext context, AppState state, EncryptedFileRef ref) async {
    if (ref.missingOnDisk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File missing on disk: ${ref.fakeName}')));
      return;
    }
    // Push media viewer
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Media viewer coming soon')));
  }

  Future<void> _openFileActions(
      BuildContext context, AppState state, EncryptedFileRef ref) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => FileActionsSheet(
        fileRef: ref,
        folders: state.folders.toList(),
      ),
    );
  }

  Future<void> _viewSlideshow(
      BuildContext context, List<EncryptedFileRef> refs) async {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slideshow coming soon')));
  }

  Future<void> _playFiles(
      BuildContext context, List<EncryptedFileRef> refs) async {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Media player coming soon')));
  }

  Future<void> _exportSelected(
    BuildContext context,
    AppState state,
    List<EncryptedFileRef> refs,
    List<VirtualFolder> folders,
  ) async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;

    state.setStatus('Exporting ${refs.length} file(s)...');
    try {
      final results = await AppDi.exportService.exportFiles(refs: refs, destDir: dir);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${results.length} file(s) to $dir')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      state.setStatus(null);
      _clearSelection();
    }
  }

  Future<void> _deleteSelected(
    BuildContext context,
    AppState state,
    List<EncryptedFileRef> refs,
    List<VirtualFolder> folders,
  ) async {
    final alsoDeleteDisk = await _confirmDeleteDialog(context, refs.length);
    if (alsoDeleteDisk == null) return;

    for (final ref in refs) {
      try {
        if (alsoDeleteDisk) {
          await AppDi.crypto.secureDelete(ref.diskPath);
        }
        await AppDi.database.deleteFileRef(ref.id);
        state.removeRef(ref.id);
      } catch (e) {
        await AppDi.logs.error('HomeScreen', 'Delete failed for ${ref.id}: $e');
      }
    }
    _clearSelection();
  }

  Future<bool?> _confirmDeleteDialog(BuildContext context, int count) {
    bool deleteDisk = false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Delete selected'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remove $count item(s) from the vault?'),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Also delete files from disk'),
                subtitle: const Text('Securely overwrites and removes the encrypted files'),
                value: deleteDisk,
                onChanged: (v) => setS(() => deleteDisk = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, deleteDisk),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  void _onOverflowMenu(BuildContext context, AppState state, String value) {
    switch (value) {
      case 'new_folder':
        _createFolder(context, state);
      case 'download':
        _showDownloadDialog(context, state);
      case 'search':
        _showSearchDialog(context, state);
      case 'sort_name_asc':
        state.sortFiles(SortMode.nameAsc, folderId: _currentFolderId);
      case 'sort_name_desc':
        state.sortFiles(SortMode.nameDesc, folderId: _currentFolderId);
      case 'sort_created_desc':
        state.sortFiles(SortMode.createdDesc, folderId: _currentFolderId);
      case 'sort_modified_desc':
        state.sortFiles(SortMode.modifiedDesc, folderId: _currentFolderId);
      case 'clear_password':
        state.clearSession();
    }
  }

  Future<void> _createFolder(BuildContext context, AppState state) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: 'Folder name', hintText: 'My Folder'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final session = state.passwordVault.active;
    if (session == null) return;

    final nameEnc = state.passwordVault.encryptMetadata(name);
    final now = DateTime.now().toUtc();
    final folder = VirtualFolder(
      id: AppDi.crypto.newFileId(),
      vaultId: session.vault.id,
      nameEncrypted: nameEnc,
      parentId: _currentFolderId,
      sortIndex: state.folders.length,
      createdAt: now,
      name: name,
    );
    await AppDi.database.insertFolder(folder);
    state.addFolder(folder);
  }

  Future<void> _showDownloadDialog(BuildContext context, AppState state) async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download & Encrypt URL'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: 'URL', hintText: 'https://example.com/file.mp4'),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Download')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;

    state.setStatus('Downloading...');
    try {
      final ref = await AppDi.downloadService.downloadAndEncrypt(
        url: url,
        destDir: AppDi.appRoot,
        folderId: _currentFolderId,
        onProgress: (received, total) {
          final pct = total > 0 ? '${(received / total * 100).toStringAsFixed(0)}%' : '$received bytes';
          state.setStatus('Downloading: $pct');
        },
      );
      state.addRef(ref);
      state.setStatus('Download complete');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      state.setStatus(null);
    }
  }

  Future<void> _showSearchDialog(BuildContext context, AppState state) async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return;

    state.setStatus('Searching...');
    try {
      final result = await AppDi.searchService.searchDirectory(
        rootDir: dirPath,
        onFile: (path) => state.setStatus('Searching: $path'),
      );
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Search Results'),
            content: Text(
              '${result.found.length} encrypted files found\n'
              '${result.alreadyKnown.length} already in vault\n'
              '${result.newFiles.length} new files',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      state.setStatus(null);
    }
  }
}
