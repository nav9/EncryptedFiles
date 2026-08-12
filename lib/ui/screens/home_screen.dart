import 'dart:io';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/database/models/virtual_folder.dart';
import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:encrypted_files/ui/screens/about_screen.dart';
import 'package:encrypted_files/ui/screens/capture_screen.dart';
import 'package:encrypted_files/ui/screens/help_screen.dart';
import 'package:encrypted_files/ui/screens/image_viewer_screen.dart';
import 'package:encrypted_files/ui/screens/logs_screen.dart';
import 'package:encrypted_files/ui/screens/media_player_screen.dart';
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
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Set<String> _selectedIds = {};
  bool _selectMode = false;
  String? _currentFolderId; // null = root

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
      leadingWidth: 96,
      leading: Builder(builder: (ctx) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LockAllButton(),
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ],
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
        // Password button — always visible (spec: nav bar has a password icon)
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
        // New Folder — always visible (spec: nav bar has a folder icon);
        // prompts for the password first when the app is locked.
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: 'New Folder',
          onPressed: () => _createFolder(context, state),
        ),
        // Build dynamic icons based on settings order (import, camera, mic).
        // Always visible; each action prompts for the password when locked.
        ...AppDi.settings.navBarIcons.map((iconName) {
          switch (iconName) {
            case 'import':
              return IconButton(
                icon: const Icon(Icons.file_upload_outlined),
                tooltip: 'Import File(s)',
                onPressed: () => _importFiles(context, state),
              );
            case 'camera':
              if (isAndroid || !Platform.isIOS) {
                return IconButton(
                  icon: const Icon(Icons.camera_alt_outlined),
                  tooltip: 'Camera Capture',
                  onPressed: () => _openCamera(context, state),
                );
              }
              return const SizedBox.shrink();
            case 'mic':
              if (isAndroid || !Platform.isIOS) {
                return IconButton(
                  icon: const Icon(Icons.mic_none),
                  tooltip: 'Record Audio',
                  onPressed: () => _startAudioRecording(context, state),
                );
              }
              return const SizedBox.shrink();
            default:
              return const SizedBox.shrink();
          }
        }),
        // Sort / overflow menu — always visible
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'More options',
          onSelected: (v) => _onOverflowMenu(context, state, v),
          itemBuilder: (_) => [
            if (_selectedIds.isEmpty)
              const PopupMenuItem(value: 'new_folder', child: Text('New Folder')),
            const PopupMenuItem(value: 'download', child: Text('Download URL')),
            const PopupMenuItem(value: 'search', child: Text('Search Disk')),
            const PopupMenuItem(value: 'export_all', child: Text('Export / Decrypt All…')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'select_all', child: Text('Select all')),
            if (_selectedIds.isNotEmpty)
              const PopupMenuItem(value: 'select_none', child: Text('Select none')),
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
    final content = _buildBodyContent(context, state, theme);
    if (state.statusMessage == null) return content;

    return Column(
      children: [
        Material(
          color: theme.colorScheme.primaryContainer,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state.statusMessage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildBodyContent(BuildContext context, AppState state, ThemeData theme) {
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
              title: const Text('Back'),
              onTap: () {
                final current = state.folderById(_currentFolderId!);
                setState(() => _currentFolderId = current?.parentId);
              },
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

    final kinds = selectedRefs.map((f) => f.mediaKind).toSet();
    final canPlay =
        kinds.contains(MediaKind.audio) || kinds.contains(MediaKind.video);
    final canView = kinds.contains(MediaKind.image);
    final canRename =
        _selectedIds.length == 1 && (selectedRefs.length == 1 || selectedFolders.length == 1);

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
          if (canRename)
            IconButton(
              icon: const Icon(Icons.drive_file_rename_outline),
              tooltip: 'Rename',
              onPressed: () {
                if (selectedFolders.isNotEmpty) {
                  _renameFolder(context, state, selectedFolders.first);
                } else if (selectedRefs.isNotEmpty) {
                  _openFileActions(context, state, selectedRefs.first);
                }
              },
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
    final f = state.folderById(folderId);
    return f?.name ?? 'Folder';
  }

  Future<void> _showPasswordDialog(
      BuildContext context, AppState state) async {
    // Remember whether any vault already exists: on first launch the dialog
    // creates a brand-new vault, so the "No files found" snackbar would be
    // confusing (there are legitimately no files yet). Only show it when the
    // user is unlocking an existing vault that happens to have no refs.
    final hadVaults = (await AppDi.database.listVaults()).isNotEmpty;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PasswordDialog(),
    );
    if (result == true && mounted) {
      await state.loadVaultContents();
      // Spec: if no file references match this password, inform the user.
      if (hadVaults && state.fileRefs.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No files found for this password')),
        );
      }
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

  /// Ensures an active password session exists; if not, prompts for the
  /// password (or creates the first vault). Returns whether a session is
  /// active afterwards.
  Future<bool> _ensureSession(BuildContext context, AppState state) async {
    if (state.hasSession) return true;
    await _showPasswordDialog(context, state);
    return state.hasSession;
  }

  Future<void> _importFiles(BuildContext context, AppState state) async {
    if (!await _ensureSession(context, state)) return;
    final hasStorage = await AppDi.permissions.requestStorage();
    if (!hasStorage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission denied')),
        );
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final targetFolderId = await _chooseImportFolder(context, state);
    if (!mounted) return;
    if (targetFolderId == _FolderChoice.cancelled) return;

    state.setStatus('Importing ${result.files.length} file(s)...');
    try {
      for (final file in result.files) {
        if (file.path == null) continue;
        final ref = await AppDi.importService.importFile(
          sourcePath: file.path!,
          destDir: AppDi.appRoot,
          folderId: targetFolderId,
        );
        state.addRef(ref);
      }
      state.setStatus('Import complete');
      if (mounted && targetFolderId != _currentFolderId) {
        setState(() => _currentFolderId = targetFolderId);
      }
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

  Future<String?> _chooseImportFolder(BuildContext context, AppState state) async {
    if (_currentFolderId != null) return _currentFolderId;
    if (state.folders.isEmpty) {
      final create = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Create a folder'),
          content: const Text('Create a virtual folder to store these file references.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () => Navigator.pop(ctx, true),
              label: const Text('Create Folder'),
            ),
          ],
        ),
      );
      if (create != true || !mounted) return _FolderChoice.cancelled;
      final folder = await _createFolder(context, state, returnCreated: true);
      return folder?.id ?? _FolderChoice.cancelled;
    }

    final choice = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Import to Folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Root'),
                onTap: () => Navigator.pop(ctx, null),
              ),
              ...state.folders.map(
                (folder) => ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name ?? 'Folder'),
                  subtitle: Text('${folder.fileCount} file(s)'),
                  onTap: () => Navigator.pop(ctx, folder.id),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Create new folder'),
                onTap: () => Navigator.pop(ctx, _FolderChoice.create),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _FolderChoice.cancelled),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || choice == _FolderChoice.cancelled) return _FolderChoice.cancelled;
    if (choice == _FolderChoice.create) {
      final folder = await _createFolder(context, state, returnCreated: true);
      return folder?.id ?? _FolderChoice.cancelled;
    }
    return choice;
  }

  Future<void> _openCamera(BuildContext context, AppState state) async {
    if (!await _ensureSession(context, state)) return;
    final granted = await AppDi.permissions.requestCamera();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission denied')));
      return;
    }
    // Push camera screen (placeholder — full implementation in camera_screen.dart)
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CaptureScreen(
            mode: CaptureMode.camera,
            folderId: _currentFolderId,
          ),
        ),
      );
    }
  }

  Future<void> _startAudioRecording(BuildContext context, AppState state) async {
    if (!await _ensureSession(context, state)) return;
    final granted = await AppDi.permissions.requestMicrophone();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')));
      return;
    }
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CaptureScreen(
            mode: CaptureMode.microphone,
            folderId: _currentFolderId,
          ),
        ),
      );
    }
  }

  Future<void> _openFile(
      BuildContext context, AppState state, EncryptedFileRef ref) async {
    if (ref.missingOnDisk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File missing on disk: ${ref.fakeName}')));
      return;
    }
    switch (ref.mediaKind) {
      case MediaKind.image:
        final images = state
            .filesInFolder(ref.folderId)
            .where((f) => !f.missingOnDisk && f.mediaKind == MediaKind.image)
            .toList();
        final index = images.indexWhere((f) => f.id == ref.id);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageViewerScreen(
              images: images.isEmpty ? [ref] : images,
              initialIndex: index < 0 ? 0 : index,
              slideshowIntervalSec: AppDi.settings.slideshowSeconds,
            ),
          ),
        );
      case MediaKind.audio:
      case MediaKind.video:
        final playlist = state
            .filesInFolder(ref.folderId)
            .where((f) =>
                !f.missingOnDisk &&
                (f.mediaKind == MediaKind.audio || f.mediaKind == MediaKind.video))
            .toList();
        final index = playlist.indexWhere((f) => f.id == ref.id);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MediaPlayerScreen(
              playlist: playlist.isEmpty ? [ref] : playlist,
              initialIndex: index < 0 ? 0 : index,
            ),
          ),
        );
      case MediaKind.document:
      case MediaKind.other:
        await _openStreamExternally(context, ref);
    }
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
    final images =
        refs.where((f) => !f.missingOnDisk && f.mediaKind == MediaKind.image).toList();
    if (images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image files selected')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          images: images,
          slideshowMode: true,
          slideshowIntervalSec: AppDi.settings.slideshowSeconds,
        ),
      ),
    );
  }

  Future<void> _playFiles(
      BuildContext context, List<EncryptedFileRef> refs) async {
    final playlist = refs
        .where((f) =>
            !f.missingOnDisk &&
            (f.mediaKind == MediaKind.audio || f.mediaKind == MediaKind.video))
        .toList();
    if (playlist.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audio or video files selected')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaPlayerScreen(playlist: playlist),
      ),
    );
  }

  Future<void> _openStreamExternally(
    BuildContext context,
    EncryptedFileRef ref,
  ) async {
    stateMessage(AppDi.appState, 'Preparing ${ref.realName ?? ref.fakeName}...');
    try {
      final url = await AppDi.mediaService.getStreamUrl(ref);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app found to open this file type')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      stateMessage(AppDi.appState, null);
    }
  }

  void stateMessage(AppState state, String? message) => state.setStatus(message);

  Future<void> _exportAllVisible(BuildContext context, AppState state) async {
    if (!await _ensureSession(context, state)) return;
    final refs = state.fileRefs
        .where((r) =>
            _currentFolderId == null || r.folderId == _currentFolderId)
        .toList();
    if (refs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No files in this view to export')),
        );
      }
      return;
    }
    await _exportSelected(context, state, refs, const []);
  }

  Future<void> _exportSelected(
    BuildContext context,
    AppState state,
    List<EncryptedFileRef> refs,
    List<VirtualFolder> folders,
  ) async {
    final exportRefs = _expandSelectedRefs(state, refs, folders);
    if (exportRefs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file references selected for export')),
      );
      return;
    }

    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;

    final writable = await _canWriteToDirectory(dir);
    if (!writable && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot write to $dir'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!mounted) return;
    final results = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExportProgressDialog(refs: exportRefs, destDir: dir),
    );
    if (mounted && results != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${results.length} file(s) to $dir')),
      );
      _clearSelection();
    }
  }

  Future<void> _deleteSelected(
    BuildContext context,
    AppState state,
    List<EncryptedFileRef> refs,
    List<VirtualFolder> folders,
  ) async {
    final folderIds = _descendantFolderIds(state, folders);
    final allRefs = _expandSelectedRefs(state, refs, folders);
    final alsoDeleteDisk = await _confirmDeleteDialog(
      context,
      allRefs.length,
      folders.length,
    );
    if (alsoDeleteDisk == null) return;

    if (alsoDeleteDisk) {
      final confirmed = await _confirmDiskDeleteDialog(context, allRefs.length);
      if (confirmed != true) return;
    }

    for (final ref in allRefs) {
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

    for (final folderId in folderIds.toList().reversed) {
      try {
        await AppDi.database.deleteFolder(folderId);
      } catch (e) {
        await AppDi.logs.error('HomeScreen', 'Folder delete failed for $folderId: $e');
      }
    }
    state.removeFolders(folderIds);
    if (_currentFolderId != null && folderIds.contains(_currentFolderId)) {
      setState(() => _currentFolderId = null);
    }
    _clearSelection();
  }

  Future<bool?> _confirmDeleteDialog(
    BuildContext context,
    int fileCount,
    int folderCount,
  ) {
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
              Text(
                'Remove $fileCount file reference(s)'
                '${folderCount > 0 ? ' and $folderCount folder(s)' : ''} from the vault?',
              ),
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

  Future<bool?> _confirmDiskDeleteDialog(BuildContext context, int count) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete files from disk?'),
        content: Text(
          'This will permanently delete $count encrypted file(s) from disk. '
          'They cannot be opened again from this app even with the correct password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete from Disk'),
          ),
        ],
      ),
    );
  }

  Set<String> _descendantFolderIds(AppState state, List<VirtualFolder> folders) {
    final result = <String>{};
    void visit(String id) {
      if (!result.add(id)) return;
      for (final child in state.folders.where((f) => f.parentId == id)) {
        visit(child.id);
      }
    }

    for (final folder in folders) {
      visit(folder.id);
    }
    return result;
  }

  List<EncryptedFileRef> _expandSelectedRefs(
    AppState state,
    List<EncryptedFileRef> refs,
    List<VirtualFolder> folders,
  ) {
    final ids = <String>{};
    final out = <EncryptedFileRef>[];
    void add(EncryptedFileRef ref) {
      if (ids.add(ref.id)) out.add(ref);
    }

    for (final ref in refs) {
      add(ref);
    }

    final folderIds = _descendantFolderIds(state, folders);
    for (final ref in state.fileRefs) {
      if (ref.folderId != null && folderIds.contains(ref.folderId)) {
        add(ref);
      }
    }
    return out;
  }

  Future<bool> _canWriteToDirectory(String dir) async {
    try {
      await Directory(dir).create(recursive: true);
      final probe = File(
        '$dir/.encrypted_files_write_${DateTime.now().microsecondsSinceEpoch}',
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onOverflowMenu(BuildContext context, AppState state, String value) {
    switch (value) {
      case 'new_folder':
        _createFolder(context, state);
      case 'download':
        _showDownloadDialog(context, state);
      case 'search':
        _showSearchDialog(context, state);
      case 'export_all':
        _exportAllVisible(context, state);
      case 'select_all':
        _selectAllVisible(state);
      case 'select_none':
        _clearSelection();
      case 'sort_name_asc':
        state.sortCurrentView(SortMode.nameAsc, folderId: _currentFolderId);
      case 'sort_name_desc':
        state.sortCurrentView(SortMode.nameDesc, folderId: _currentFolderId);
      case 'sort_created_desc':
        state.sortCurrentView(SortMode.createdDesc, folderId: _currentFolderId);
      case 'sort_modified_desc':
        state.sortCurrentView(SortMode.modifiedDesc, folderId: _currentFolderId);
      case 'clear_password':
        state.clearSession();
    }
  }

  void _selectAllVisible(AppState state) {
    final folders = state.subFolders(_currentFolderId);
    final files = state.filesInFolder(_currentFolderId);
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(folders.map((f) => f.id))
        ..addAll(files.map((f) => f.id));
      _selectMode = _selectedIds.isNotEmpty;
    });
  }

  Future<VirtualFolder?> _createFolder(
    BuildContext context,
    AppState state, {
    bool returnCreated = false,
  }) async {
    if (!await _ensureSession(context, state)) return null;
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
    if (name == null || name.isEmpty) return null;

    final session = state.passwordVault.active;
    if (session == null) return null;

    final nameEnc = state.passwordVault.encryptMetadata(name);
    final now = DateTime.now().toUtc();
    final folder = VirtualFolder(
      id: AppDi.crypto.newFileId(),
      vaultId: session.vault.id,
      nameEncrypted: nameEnc,
      parentId: _currentFolderId,
      sortIndex: state.folders.length,
      createdAt: now,
      modifiedAt: now,
      name: name,
    );
    await AppDi.database.insertFolder(folder);
    state.addFolder(folder);
    return returnCreated ? folder : null;
  }

  Future<void> _renameFolder(
    BuildContext context,
    AppState state,
    VirtualFolder folder,
  ) async {
    final ctrl = TextEditingController(text: folder.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;

    try {
      final updated = folder.copyWith(
        name: name,
        nameEncrypted: state.passwordVault.encryptMetadata(name),
        modifiedAt: DateTime.now().toUtc(),
      );
      await AppDi.database.updateFolder(updated);
      state.updateFolder(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed folder to "$name"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rename failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showDownloadDialog(BuildContext context, AppState state) async {
    if (!await _ensureSession(context, state)) return;
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
    if (!await _ensureSession(context, state)) return;
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

class _FolderChoice {
  static const String cancelled = '__cancelled__';
  static const String create = '__create__';
}

class _ExportProgressDialog extends StatefulWidget {
  const _ExportProgressDialog({
    required this.refs,
    required this.destDir,
  });

  final List<EncryptedFileRef> refs;
  final String destDir;

  @override
  State<_ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends State<_ExportProgressDialog> {
  final Map<String, String> _results = {};
  int _done = 0;
  bool _paused = false;
  bool _cancelled = false;
  bool _finished = false;
  String _current = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(_run);
  }

  Future<void> _run() async {
    for (final ref in widget.refs) {
      while (_paused && !_cancelled && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (_cancelled || !mounted) break;

      setState(() => _current = ref.realName ?? ref.fakeName);
      try {
        final path = await AppDi.exportService.exportFile(
          ref: ref,
          destDir: widget.destDir,
        );
        _results[ref.id] = path;
      } catch (e) {
        await AppDi.logs.error('ExportProgress', 'Failed to export ${ref.id}: $e');
      }
      if (mounted) setState(() => _done++);
    }
    if (mounted) {
      setState(() {
        _finished = true;
        _current = _cancelled ? 'Cancelled' : 'Complete';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.refs.length;
    final value = total == 0 ? 0.0 : _done / total;
    return AlertDialog(
      title: const Text('Export Unencrypted'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: _finished ? 1 : value),
          const SizedBox(height: 12),
          Text('$_done of $total file(s) processed'),
          const SizedBox(height: 4),
          Text(
            _current,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        if (!_finished)
          TextButton(
            onPressed: () => setState(() => _paused = !_paused),
            child: Text(_paused ? 'Resume' : 'Pause'),
          ),
        if (!_finished)
          TextButton(
            onPressed: () {
              setState(() => _cancelled = true);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
        if (_finished)
          FilledButton(
            onPressed: () => Navigator.pop(context, _results),
            child: const Text('Done'),
          ),
      ],
    );
  }
}
