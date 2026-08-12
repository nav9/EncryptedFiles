import 'dart:async';

import 'package:encrypted_files/core/constants.dart';
import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/core/exceptions.dart';
import 'package:flutter/material.dart';

/// Password entry dialog.
///
/// Supports:
/// * Unlocking or creating a vault.
/// * Plausible deniability: optional second password field.
///   – If both passwords match, the second is ignored.
///   – If they differ, the user chooses "Re-type" or "Use plausibly".
///     Using plausibly stores the second password as a decoy vault.
/// * Anti-brute-force countdown for unrecognised passwords.
/// * Decoy detection: shows fake "corrupt bytes" progress when decoy is used.
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key});

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _ctrl1 = TextEditingController();
  final _ctrl2 = TextEditingController();
  final _focus1 = FocusNode();

  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;
  bool _showDecoy = false; // fake progress for plausible deniability
  String? _error;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _ctrl1.dispose();
    _ctrl2.dispose();
    _focus1.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw1 = _ctrl1.text;
    final pw2 = _ctrl2.text;

    if (pw1.isEmpty) return;

    // If both passwords are identical (or second is empty), ignore second.
    if (pw2.isEmpty || pw1 == pw2) {
      await _unlock(pw1, null);
      return;
    }

    // Passwords differ — ask user what to do.
    if (!mounted) return;
    final choice = await showDialog<_DeniabilityChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeniabilityDialog(),
    );

    if (!mounted) return;
    if (choice == _DeniabilityChoice.retype) {
      _ctrl1.clear();
      _ctrl2.clear();
      _focus1.requestFocus();
      return;
    }
    if (choice == _DeniabilityChoice.usePlausibly) {
      await _unlock(pw1, pw2);
    }
  }

  Future<void> _unlock(String mainPw, String? decoyPw) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Unlock the vault (or create it on first launch). This also creates the
      // decoy vault if a decoy password is provided.
      final session = await AppDi.passwordVault.unlockOrCreate(mainPw);

      if (session == null) {
        _startDelay('Unrecognized password. Please try again.');
        return;
      }

      if (decoyPw != null && decoyPw.isNotEmpty) {
        // Spin up the decoy vault in background; errors are non-fatal.
        await AppDi.passwordVault
            .createDecoyVault(decoyPw)
            .catchError((_) {});
      }

      // If the matched vault is a decoy, show fake decrypt UI.
      if (session.isDecoy) {
        await _showDecoyAnimation();
        return;
      }

      // Start stream server with real session.
      if (AppDi.streamServer.isRunning) {
        AppDi.streamServer.stop();
      }
      AppDi.streamServer.start(session);

      if (mounted) Navigator.pop(context, true);
    } on EfAuthException {
      _startDelay('Unrecognized password. Please try again.');
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _showDecoyAnimation() async {
    setState(() {
      _loading = false;
      _showDecoy = true;
    });
    // Fake progress for ~1.5 seconds.
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    // Clear the decoy session from RAM immediately.
    await AppDi.passwordVault.clearActive();
    setState(() => _showDecoy = false);
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber, color: Colors.amber),
          const SizedBox(width: 8),
          const Text('Decryption complete'),
        ]),
        content: const Text(
          'Decryption successful. Unable to display media due to possibly corrupt bytes.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, false);
  }

  void _startDelay(String msg) {
    setState(() {
      _error = msg;
      _loading = false;
      _countdown = AppConstants.unrecognizedPasswordDelaySec;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        setState(() => _error = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_showDecoy) {
      return AlertDialog(
        title: const Text('Decrypting…'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 12),
            Text('Please wait while files are decrypted…'),
          ],
        ),
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Enter Password'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Primary password field
            TextField(
              controller: _ctrl1,
              focusNode: _focus1,
              obscureText: _obscure1,
              enabled: !_loading && _countdown == 0,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure1 = !_obscure1),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            // Second (deniability) password field
            TextField(
              controller: _ctrl2,
              obscureText: _obscure2,
              enabled: !_loading && _countdown == 0,
              decoration: InputDecoration(
                labelText: 'Re-type password (optional)',
                hintText: 'Leave blank or match above to ignore',
                border: const OutlineInputBorder(),
                helperText: 'If different, enables plausible deniability',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure2 = !_obscure2),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _countdown > 0
                    ? '$_error  (wait $_countdown s…)'
                    : _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_loading || _countdown > 0) ? null : _submit,
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}

enum _DeniabilityChoice { retype, usePlausibly }

class _DeniabilityDialog extends StatelessWidget {
  const _DeniabilityDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwords do not match'),
      content: const Text(
        'Use second password plausibly or re-type passwords?\n\n'
        '"Use plausibly" will make the second password act as a decoy: '
        'entering it in the future will show a fake "corrupt bytes" message '
        'instead of real files.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _DeniabilityChoice.retype),
          child: const Text('Re-type'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () =>
              Navigator.pop(context, _DeniabilityChoice.usePlausibly),
          child: const Text('Use plausibly'),
        ),
      ],
    );
  }
}
