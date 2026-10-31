import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/services/google_drive_sign_in_button.dart';
import 'package:streak/services/google_drive_sync.dart';
import 'package:streak/services/cloud_sync_config.dart';

class GoogleDrivePage extends StatefulWidget {
  const GoogleDrivePage({super.key});

  @override
  State<GoogleDrivePage> createState() => _GoogleDrivePageState();
}

class _GoogleDrivePageState extends State<GoogleDrivePage> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  bool _busy = false;
  bool _wrongPassphrase = false;
  bool _restoring =
      CloudSyncConfig.googleDriveConfigured && GoogleDriveSync.account == null;
  String? _message;

  GoogleSignInAccount? get _user => GoogleDriveSync.account;

  @override
  void initState() {
    super.initState();
    GoogleDriveSync.status.addListener(_onSyncStatus);
    _events = GoogleSignIn.instance.authenticationEvents.listen(
      (event) {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn():
            GoogleDriveSync.setAccount(event.user);
          case GoogleSignInAuthenticationEventSignOut():
            GoogleDriveSync.setAccount(null);
        }
        if (mounted) setState(() {});
      },
      onError: (Object error) {
        if (error is GoogleSignInException &&
            (error.code == GoogleSignInExceptionCode.canceled ||
                error.code == GoogleSignInExceptionCode.interrupted ||
                error.code == GoogleSignInExceptionCode.uiUnavailable)) {
          return;
        }
        if (mounted) {
          setState(
            () => _message =
                'Could not restore Google sign-in. Please sign in again.',
          );
        }
      },
    );
    if (CloudSyncConfig.googleDriveConfigured) {
      unawaited(_initialize());
    }
  }

  void _onSyncStatus() {
    if (mounted && !_busy && GoogleDriveSync.status.value == 'Syncing…') {
      setState(() => _message = null);
    }
  }

  Future<void> _initialize() async {
    try {
      await GoogleDriveSync.restoreSession();
    } on GoogleSignInException catch (error) {
      if (mounted) {
        setState(
          () => _message =
              'Could not restore Google sign-in '
              '(${error.code.name}). Please sign in again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not restore Google sign-in. Please sign in again.',
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  void dispose() {
    GoogleDriveSync.status.removeListener(_onSyncStatus);
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

  Future<void> _sync({bool changePassphrase = false}) async {
    await _run(() async {
      var passphrase = changePassphrase
          ? null
          : await GoogleDriveSync.savedPassphrase();
      var newPassphrase = false;
      if (passphrase == null && mounted) {
        passphrase = await _askPassphrase(context);
        if (passphrase == null) return;
        newPassphrase = true;
      }
      if (passphrase == null) return;
      await LocalStore.writeSetting('driveSyncTracking', true);
      GoogleDriveSync.startAutoSync();
      final merged = await GoogleDriveSync.sync(passphrase: passphrase);
      if (newPassphrase) await GoogleDriveSync.savePassphrase(passphrase);
      await LocalStore.writeSetting('driveSyncEnabled', true);
      if (mounted) {
        setState(() {
          _wrongPassphrase = false;
          _message = 'Sync complete. $merged changes merged.';
        });
      }
    });
  }

  Future<String?> _askPassphrase(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (_) => const DrivePassphraseDialog(),
    );
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
    } on SecretBoxAuthenticationError {
      if (mounted) {
        setState(() {
          _wrongPassphrase = true;
          _message =
              'Could not unlock the Drive backup. Check the passphrase and try again.';
        });
      }
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
                  if (user == null && !CloudSyncConfig.googleDriveConfigured)
                    const Text(
                      'Google Drive sign-in is not configured in this build.',
                    ),
                  if (user == null &&
                      CloudSyncConfig.googleDriveConfigured &&
                      kIsWeb)
                    SizedBox(
                      height: 44,
                      child: googleDriveSignInButton(),
                    ),
                  if (user == null &&
                      CloudSyncConfig.googleDriveConfigured &&
                      !kIsWeb)
                    FilledButton.icon(
                      onPressed: _busy || _restoring ? null : _connect,
                      icon: const Icon(Icons.login),
                      label: Text(
                        _restoring
                            ? 'Restoring sign-in…'
                            : 'Sign in with Google',
                      ),
                    ),
                  if (user != null) ...[
                    FilledButton.icon(
                      onPressed: _busy || !GoogleDriveSync.encryptionReady
                          ? null
                          : () => _sync(),
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
                    if (_wrongPassphrase)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _sync(changePassphrase: true),
                        child: const Text('Try another passphrase'),
                      ),
                    ValueListenableBuilder<String?>(
                      valueListenable: GoogleDriveSync.status,
                      builder: (context, status, _) =>
                          status == null || _message != null
                          ? const SizedBox.shrink()
                          : Text(status),
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

class DrivePassphraseDialog extends StatefulWidget {
  const DrivePassphraseDialog({super.key});

  @override
  State<DrivePassphraseDialog> createState() => _DrivePassphraseDialogState();
}

class _DrivePassphraseDialogState extends State<DrivePassphraseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Protect Drive sync'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Sync passphrase',
          helperText: 'Use the same passphrase on every device.',
        ),
        validator: (value) => (value?.trim().length ?? 0) < 12
            ? 'Use at least 12 characters.'
            : null,
        onFieldSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Use passphrase')),
    ],
  );
}
