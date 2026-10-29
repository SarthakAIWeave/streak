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
      final merged = await GoogleDriveSync.pullAndMerge();
      await GoogleDriveSync.upload();
      if (mounted) {
        setState(() => _message = 'Sync complete. $merged changes merged.');
      }
    });
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
                        ? 'Connect Drive for optional sync. Encrypted sync will be enabled before data upload.'
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
                            : 'Sync pending encryption',
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
            'End-to-end encryption is required before any progress is uploaded. '
            'You can keep using the app offline without signing in.',
          ),
        ],
      ),
    );
  }
}
