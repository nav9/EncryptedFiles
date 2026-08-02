import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/database/models/virtual_folder.dart';
import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Context-menu style bottom sheet for per-file actions:
/// rename real name, move to a different virtual folder, copy to a folder.
class FileActionsSheet extends StatefulWidget {
  const FileActionsSheet({
    super.key,
    required this.fileRef,
    required this.folders,
  });

  final EncryptedFileRef fileRef;
  final List<VirtualFolder> folders;

  @override
  State<FileActionsSheet> createState() => _FileActionsSheetState();
}

class _FileActionsSheetState extends State<FileActionsSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title chip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                widget.fileRef.realName ?? widget.fileRef.fakeName,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(context);
                await _renameDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('Move to folder…'),
              onTap: () async {
                Navigator.pop(context);
                await _moveCopyDialog(context, copy: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy to folder…'),
              onTap: () async {
                Navigator.pop(context);
                await _moveCopyDialog(context, copy: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameDialog(BuildContext context) async {
    final ctrl = TextEditingController(
      text: widget.fileRef.realName ?? widget.fileRef.fakeName,
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'New real name',
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
    if (newName == null || newName.isEmpty) return;
    if (!context.mounted) return;

    try {
      // Re-encrypt the new real name.
      final newNameEnc = AppDi.passwordVault.encryptMetadata(newName);
      final updated = widget.fileRef.copyWith(
        realName: newName,
        realNameEncrypted: newNameEnc,
        modifiedAt: DateTime.now().toUtc(),
      );
      await AppDi.database.updateFileRef(updated);
      if (context.mounted) {
        context.read<AppState>().updateRef(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to "$newName"')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Rename failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _moveCopyDialog(BuildContext context,
      {required bool copy}) async {
    // Let user pick: null = root, or a folder id.
    String? chosenFolderId = widget.fileRef.folderId;

    final choice = await showDialog<String?>(
      context: context,
      builder: (ctx) => _FolderPickerDialog(
        folders: widget.fileRef.folderId == null
            ? widget.folders
            : [
                // Synthetic "root" entry
                VirtualFolder(
                  id: '__root__',
                  vaultId: widget.fileRef.vaultId,
                  nameEncrypted: [],
                  parentId: null,
                  sortIndex: 0,
                  createdAt: DateTime.now(),
                  name: '/ Root',
                ),
                ...widget.folders
                    .where((f) => f.id != widget.fileRef.folderId),
              ],
        currentFolderId: widget.fileRef.folderId,
      ),
    );
    if (!context.mounted) return;
    if (choice == null) return; // cancelled

    final targetFolderId = choice == '__root__' ? null : choice;

    try {
      if (copy) {
        // Create a new DB entry with a new id.
        final newRef = EncryptedFileRef(
          id: AppDi.crypto.newFileId(),
          vaultId: widget.fileRef.vaultId,
          diskPath: widget.fileRef.diskPath,
          fakeName: widget.fileRef.fakeName,
          realNameEncrypted: widget.fileRef.realNameEncrypted,
          mimeEncrypted: widget.fileRef.mimeEncrypted,
          fileBlindTag: widget.fileRef.fileBlindTag,
          sizeBytes: widget.fileRef.sizeBytes,
          folderId: targetFolderId,
          sortIndex: 0,
          createdAt: DateTime.now().toUtc(),
          modifiedAt: DateTime.now().toUtc(),
          realName: widget.fileRef.realName,
          mimeType: widget.fileRef.mimeType,
        );
        await AppDi.database.insertFileRef(newRef);
        context.read<AppState>().addRef(newRef);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File copied to folder')),
        );
      } else {
        final updated = widget.fileRef.copyWith(
          folderId: targetFolderId,
          modifiedAt: DateTime.now().toUtc(),
        );
        await AppDi.database.updateFileRef(updated);
        context.read<AppState>().updateRef(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File moved to folder')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${copy ? "Copy" : "Move"} failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }
}

/// Dialog that lets the user pick a destination virtual folder.
class _FolderPickerDialog extends StatelessWidget {
  const _FolderPickerDialog({
    required this.folders,
    required this.currentFolderId,
  });

  final List<VirtualFolder> folders;
  final String? currentFolderId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Destination Folder'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: folders.map((f) {
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(f.name ?? f.id),
              selected: f.id == currentFolderId,
              onTap: () => Navigator.pop(context, f.id),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
