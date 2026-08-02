import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:encrypted_files/ui/widgets/lock_all_button.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) => setState(() => _info = i));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        actions: const [LockAllButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Icon(Icons.security,
                  size: 72, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'EncryptedFiles',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                _info != null
                    ? 'Version ${_info!.version} (build ${_info!.buildNumber})'
                    : 'Loading…',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(height: 32),
            _item('Encryption', 'XChaCha20-Poly1305 (Monocypher)'),
            _item('KDF', 'Argon2id (memory-hard, low-RAM tuned)'),
            _item('Blind Indexing', 'BLAKE2b keyed HMAC'),
            _item('Streaming', 'Native C localhost HTTP server'),
            _item('Database', 'SQLite with encrypted metadata'),
            _item('Platforms',
                'Android (7+), Linux, Windows, macOS'),
            const SizedBox(height: 32),
            Text(
              'Built for maximum security on low-resource devices. '
              'All keys are wiped from RAM on session clear. '
              'No plaintext is ever written to disk during media playback.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
