import 'package:encrypted_files/database/models/encrypted_file_ref.dart';
import 'package:encrypted_files/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FileCard extends StatelessWidget {
  const FileCard({
    super.key,
    required this.fileRef,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onCheckChanged,
  });

  final EncryptedFileRef fileRef;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<bool?> onCheckChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = fileRef.realName ?? fileRef.fakeName;
    final fmt = DateFormat('d MMM yyyy, HH:mm');

    return Card(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 42,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: isSelected,
                      onChanged: onCheckChanged,
                      visualDensity: VisualDensity.compact,
                    ),
                    const Icon(Icons.drag_handle, size: 18),
                  ],
                ),
              ),
              // Icon
              _MediaIcon(kind: fileRef.mediaKind),
              const SizedBox(width: 8),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (fileRef.missingOnDisk)
                          const Icon(Icons.warning_amber,
                              size: 14, color: Colors.amber),
                      ],
                    ),
                    Text(
                      'Fake: ${fileRef.fakeName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    Text(
                      fileRef.diskPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline, fontSize: 10),
                    ),
                    Row(
                      children: [
                        Text(
                          _fmtSize(fileRef.sizeBytes),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.primary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          fmt.format(fileRef.modifiedAt.toLocal()),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _MediaIcon extends StatelessWidget {
  const _MediaIcon({required this.kind});
  final MediaKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    IconData icon;
    Color color;
    switch (kind) {
      case MediaKind.image:
        icon = Icons.image_outlined;
        color = Colors.teal;
      case MediaKind.audio:
        icon = Icons.audio_file_outlined;
        color = Colors.purple;
      case MediaKind.video:
        icon = Icons.videocam_outlined;
        color = Colors.orange;
      case MediaKind.document:
        icon = Icons.description_outlined;
        color = Colors.blue;
      case MediaKind.other:
        icon = Icons.insert_drive_file_outlined;
        color = theme.colorScheme.outline;
    }
    return Icon(icon, color: color, size: 28);
  }
}
