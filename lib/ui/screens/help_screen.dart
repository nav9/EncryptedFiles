import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:encrypted_files/ui/widgets/lock_all_button.dart';
import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = [
    (
      q: 'What encryption does this app use?',
      a: 'XChaCha20-Poly1305 via Monocypher — a single modern AEAD cipher '
          'that works identically on Android, Linux, Windows, and macOS. '
          'There is no hardware-dependent AES, ensuring cross-platform portability.'
    ),
    (
      q: 'How does the password system work?',
      a: 'Each password derives a master key via Argon2id (memory-hard). '
          'Two sub-keys are derived: an encryption key (for files) and a blind key '
          '(for BLAKE2b indexing). The blind index lets the app quickly find which '
          'vault belongs to your password without revealing anything.'
    ),
    (
      q: 'Are my files safe if I lose my phone?',
      a: 'Yes. Every file on disk is fully encrypted. Without the password, '
          'the data is mathematically unrecoverable. The fake filenames on disk '
          'give no hint about the real contents.'
    ),
    (
      q: 'How do I import a file?',
      a: 'Enter your password first, then tap the ↑ (upload) icon in the toolbar. '
          'Select one or more files. They will be encrypted and added to your vault. '
          'The originals are not deleted — you can remove them manually.'
    ),
    (
      q: 'How do I export (decrypt) a file?',
      a: 'Select files using long-press or the checkbox, then tap the export icon '
          'in the bottom bar. Choose a destination folder. The decrypted files will '
          'be written there with their original filenames.'
    ),
    (
      q: 'What happens if a file is missing from disk?',
      a: 'The app shows a warning icon on the file card. Use the overflow menu → '
          '"Search Disk" to let the app search a directory for moved files. '
          'If found, the database reference is updated automatically.'
    ),
    (
      q: 'Can I use the same password on multiple devices?',
      a: 'Yes. Encrypted files (.ef format) are fully portable across all platforms. '
          'Copy the encrypted files and the database to the new device, use the same '
          'password, and everything will work.'
    ),
    (
      q: 'What does "Clear Password" do?',
      a: 'It immediately wipes all cryptographic keys from RAM, stops the streaming '
          'server, and hides all file references. No data is deleted from disk. '
          'It is equivalent to locking the vault.'
    ),
    (
      q: 'What chunk size should I use?',
      a: 'The app auto-suggests a chunk size based on your device RAM. '
          'For low-RAM devices (≤ 1 GB), 32 KB is recommended. '
          'For desktops with ample RAM, 256 KB–1 MB gives better throughput.'
    ),
    (
      q: 'Is camera/microphone capture secure?',
      a: 'Photos are read into RAM and encrypted immediately. Audio is recorded '
          'to a temporary file (required by OS APIs), then encrypted and the temp '
          'file is deleted. On Android 10+, temp files use app-private storage '
          'that is not accessible to other apps.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & FAQ'),
        actions: const [LockAllButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Frequently Asked Questions',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ..._faqs.map(
            (faq) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                title: Text(faq.q,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(faq.a, style: theme.textTheme.bodySmall),
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
