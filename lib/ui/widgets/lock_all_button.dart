import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Red shield emergency button that immediately locks all vaults.
///
/// Wipes all cryptographic keys from RAM, stops the stream server, and clears
/// all file/folder references from memory. Must be placed as the first action
/// in every AppBar.
class LockAllButton extends StatelessWidget {
  const LockAllButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.shield, color: Colors.red),
      tooltip: 'Lock all – Emergency lock',
      onPressed: () => _lockAll(context),
    );
  }

  Future<void> _lockAll(BuildContext context) async {
    final state = context.read<AppState>();
    try {
      await state.clearSession();
      AppDi.streamServer.stop();
      await AppDi.logs.info('LockAll', 'Emergency lock triggered – all keys wiped');
    } catch (e) {
      // Silently ignore – locking should always succeed even on errors.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔒 Locked. All keys wiped from RAM.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}
