import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:streak/services/google_drive_sign_in_button.dart';
import 'package:streak/services/google_drive_sync.dart';

class GoogleDrivePage extends StatefulWidget {
  const GoogleDrivePage({super.key});

  @override
  State<GoogleDrivePage> createState() => _GoogleDrivePageState();
}

class _GoogleDrivePageState extends State<GoogleDrivePage> {
  StreamSubscription<Object?>? _events;
  bool _busy = false;
  String? _message;

  GoogleSignInAccount? get _user => GoogleDriveSync.account;

  @override
  void initState() {
    super.initState();
    _events = GoogleSignIn.instance.authenticationEvents.listen((event) {
      final dynamic value = event;
      try {
        GoogleDriveSync.setAccount(value.user as GoogleSignInAccount?);
      } catch (_) {}
      if (mounted) setState(() {});
    });
    unawaited(GoogleDriveSync.initialize());
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _connect() async {
    if (kIsWeb) return;
    await _run(() async {
      await GoogleDriveSync.signIn();
      if (mounted) setState(() => _message = 'Google Drive connected.');
    });
  }

  Future<void> _sync() async {
    await _run(() async {
      var passphrase = await GoogleDriveSync.savedPassphrase();
      var newPassphrase = false;
      if (passphrase == null && mounted) {
        passphrase = await _askPassphrase(context);
        if (passphrase == null) return;
        newPassphrase = true;
      }
      if (passphrase == null) return;
      final merged = await GoogleDriveSync.pullAndMerge(passphrase: passphrase);
      await GoogleDriveSync.upload(passphrase: passphrase);
      if (newPassphrase) await GoogleDriveSync.savePassphrase(passphrase);
      GoogleDriveSync.startAutoSync();
      if (mounted) {
        setState(() => _message = 'Sync complete. $merged changes merged.');
      }
    });
  }

  Future<String?> _askPassphrase(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Protect Drive sync'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Sync passphrase',
            helperText: 'Use the same passphrase on every device.',
          ),
          onSubmitted: (_) {
            final value = controller.text.trim();
            if (value.length >= 12) Navigator.of(context).pop(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length < 12) return;
              Navigator.of(context).pop(value);
            },
            child: const Text('Use passphrase'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _disconnect() async {
    await _run(() async {
      await GoogleDriveSync.signOut();
      if (mounted) setState(() => _message = 'Google Drive disconnected.');
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = 'Sync could not complete: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.cloud, size: 28),
                  const SizedBox(height: 16),
                  Text(
                    user == null ? 'Connect Google Drive' : 'Drive connected',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user == null
                        ? 'Connect Drive for optional sync. Your data is encrypted before upload.'
                        : user.email,
                  ),
                  const SizedBox(height: 20),
                  if (user == null && kIsWeb)
                    SizedBox(
                      height: 44,
                      child: googleDriveSignInButton(),
                    ),
                  if (user == null && !kIsWeb)
                    FilledButton.icon(
                      onPressed: _busy ? null : _connect,
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in with Google'),
                    ),
                  if (user != null) ...[
                    FilledButton.icon(
                      onPressed: _busy || !GoogleDriveSync.encryptionReady
                          ? null
                          : _sync,
                      icon: const Icon(LucideIcons.refreshCw),
                      label: Text(
                        _busy
                            ? 'Syncing…'
                            : GoogleDriveSync.encryptionReady
                            ? 'Sync now'
                            : 'Sync unavailable',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _disconnect,
                      icon: const Icon(Icons.logout),
                      label: const Text('Disconnect Google Drive'),
                    ),
                  ],
                  if (_message case final message?) ...[
                    const SizedBox(height: 12),
                    Text(message),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Streak requests access only to its own hidden Drive app data. '
            'Your progress is encrypted on this device before upload. Keep your '
            'sync passphrase safe; Google cannot recover it. '
            'You can keep using the app offline without signing in.',
          ),
        ],
      ),
    );
  }
}
