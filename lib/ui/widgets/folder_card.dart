import 'package:encrypted_files/database/models/virtual_folder.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FolderCard extends StatelessWidget {
  const FolderCard({
    super.key,
    required this.folder,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onCheckChanged,
  });

  final VirtualFolder folder;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<bool?> onCheckChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = folder.name ?? '(encrypted folder)';
    final fmt = DateFormat('d MMM yyyy');

    return Card(
      color: isSelected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: isSelected,
                onChanged: onCheckChanged,
                visualDensity: VisualDensity.compact,
              ),
              Icon(Icons.folder_outlined,
                  color: Colors.amber, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${folder.fileCount} file(s) · ${fmt.format(folder.createdAt.toLocal())}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
              const Icon(Icons.drag_handle, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
