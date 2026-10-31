import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show kIsWeb, ValueNotifier, visibleForTesting;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:streak/services/backup_service.dart';
import 'package:streak/services/cloud_sync_config.dart';
import 'package:streak/services/cloud_sync_encryption.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/services/folder_sync.dart';

class GoogleDriveSync {
  const GoogleDriveSync._();

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const fileName = 'streak-sync.json';
  static const encryptionReady = true;
  static var _initialized = false;
  static Future<void>? _initializing;
  static bool _restoreAttempted = false;
  static GoogleSignInAccount? _account;
  static Timer? _autoTimer;
  static Timer? _periodicTimer;
  static bool _autoBusy = false;
  static bool _autoStarted = false;
  static bool _dirty = true;
  static int _changeRevision = 0;
  static ({String? id, String? version})? _lastRead;
  static Future<int>? _syncing;
  static Future<void> Function()? onRemoteMerged;
  static final status = ValueNotifier<String?>(null);
  static StreamSubscription<GoogleSignInAuthenticationEvent>? _authEvents;
  @visibleForTesting
  static Future<auth.AuthClient?> Function(bool interactive)? clientForTesting;

  static GoogleSignInAccount? get account => _account;

  static void setAccount(GoogleSignInAccount? account) {
    if (_account?.id != account?.id) {
      _lastRead = null;
      _dirty = true;
    }
    _account = account;
    if (account == null) stopAutoSync();
  }

  static Future<void> initialize() =>
      _initializing ??= _initialize().catchError(
        (Object error, StackTrace stack) {
          _initializing = null;
          Error.throwWithStackTrace(error, stack);
        },
      );

  static Future<void> _initialize() async {
    if (!CloudSyncConfig.googleDriveConfigured) {
      throw StateError('Google Drive sign-in is not configured in this build.');
    }
    if (!kIsWeb && !GoogleSignIn.instance.supportsAuthenticate()) return;
    _authEvents ??= GoogleSignIn.instance.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          setAccount(event.user);
          unawaited(_startIfConfigured());
        case GoogleSignInAuthenticationEventSignOut():
          setAccount(null);
      }
    }, onError: (Object _) {});
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? CloudSyncConfig.googleWebClientId : null,
      serverClientId: kIsWeb ? null : CloudSyncConfig.googleWebClientId,
    );
    _initialized = true;
  }

  static Future<void> restoreSession() async {
    await initialize();
    if (!_initialized || _restoreAttempted || _account != null) return;
    _restoreAttempted = true;
    try {
      final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
      if (attempt != null) {
        final restored = await attempt;
        if (restored != null) {
          setAccount(restored);
        } else {
          _restoreAttempted = false;
        }
      }
    } catch (_) {
      _restoreAttempted = false;
      rethrow;
    }
  }

  static Future<GoogleSignInAccount?> signIn() async {
    await initialize();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw StateError('This platform needs the Google Sign-In button.');
    }
    final account = await GoogleSignIn.instance.authenticate();
    setAccount(account);
    return account;
  }

  static Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    if (LocalStore.setting('driveSyncEnabled', false)) {
      await LocalStore.writeSetting('driveSyncTracking', true);
    }
    await LocalStore.writeSetting('driveSyncEnabled', false);
    stopAutoSync();
    setAccount(null);
  }

  /// Resume a previously configured connection without blocking app startup.
  static Future<void> resume() async {
    if (!CloudSyncConfig.googleDriveConfigured ||
        !LocalStore.setting('driveSyncEnabled', true)) {
      return;
    }
    try {
      if (await savedPassphrase() == null) return;
      await LocalStore.writeSetting('driveSyncTracking', true);
      await LocalStore.writeSetting('driveSyncEnabled', true);
      await restoreSession();
      await _startIfConfigured();
    } catch (_) {
      status.value = 'Google Drive needs attention. Open Drive sync to retry.';
    }
  }

  static Future<void> _startIfConfigured() async {
    try {
      if (_account == null || !LocalStore.setting('driveSyncEnabled', false)) {
        return;
      }
      if (await savedPassphrase() == null || _account == null) return;
      startAutoSync();
      unawaited(_runAuto());
    } catch (_) {
      status.value = 'Google Drive needs attention. Open Drive sync to retry.';
    }
  }

  static void startAutoSync() {
    if (_autoStarted) return;
    _autoStarted = true;
    LocalStore.addChangeListener(_changed);
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _runAuto(),
    );
  }

  static void stopAutoSync() {
    if (!_autoStarted) return;
    _autoStarted = false;
    _dirty = true;
    LocalStore.removeChangeListener(_changed);
    _autoTimer?.cancel();
    _periodicTimer?.cancel();
    _autoTimer = null;
    _periodicTimer = null;
  }

  static void _changed() {
    if (!_autoStarted || _account == null) return;
    _dirty = true;
    _changeRevision++;
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(seconds: 15), _runAuto);
  }

  static Future<void> _runAuto() async {
    if (_autoBusy ||
        _account == null ||
        !LocalStore.setting('driveSyncEnabled', false))
      return;
    _autoBusy = true;
    try {
      final passphrase = await savedPassphrase();
      if (passphrase == null) return;
      await sync(passphrase: passphrase, interactive: false);
    } catch (_) {
      status.value = 'Sync failed. Open Drive sync to retry.';
    } finally {
      _autoBusy = false;
    }
  }

  static Future<int> sync({
    required String passphrase,
    bool interactive = true,
  }) async {
    while (_syncing != null) {
      try {
        await _syncing;
      } catch (_) {}
    }
    final operation = _syncOnce(passphrase, interactive: interactive);
    _syncing = operation;
    try {
      return await operation;
    } finally {
      if (identical(_syncing, operation)) _syncing = null;
    }
  }

  static Future<int> _syncOnce(
    String passphrase, {
    required bool interactive,
  }) async {
    status.value = 'Syncing…';
    auth.AuthClient? client;
    try {
      final account = _account;
      if (account == null) throw StateError('Google Drive is not connected.');
      client = await _client(interactive: interactive);
      if (client == null) throw StateError('Google Drive is not connected.');
      final api = drive.DriveApi(client);
      final before = await _snapshotInfo(api);
      var merged = 0;
      if (interactive || _lastRead != before) {
        merged = await LocalStore.guardWrites(
          () => _mergeSnapshot(api, before, passphrase),
        );
        await LocalStore.idle();
        if (before.id != null) await onRemoteMerged?.call();
        if (!identical(_account, account)) {
          throw StateError('Google account changed during sync. Please retry.');
        }
        _lastRead = before;
      }
      if (!identical(_account, account)) {
        throw StateError('Google account changed during sync. Please retry.');
      }
      if (interactive || _dirty) {
        final revision = _changeRevision;
        await _uploadSnapshot(api, before, passphrase);
        if (revision == _changeRevision) _dirty = false;
      }
      status.value = 'Sync complete.';
      return merged;
    } catch (_) {
      status.value = 'Sync failed. Open Drive sync to retry.';
      rethrow;
    } finally {
      client?.close();
    }
  }

  static Future<auth.AuthClient?> _client({bool interactive = true}) async {
    if (clientForTesting case final factory?) return factory(interactive);
    final user = _account;
    if (user == null) return null;
    var authorization = await user.authorizationClient.authorizationForScopes(
      const [scope],
    );
    if (authorization == null && interactive) {
      authorization = await user.authorizationClient.authorizeScopes(const [
        scope,
      ]);
    }
    if (authorization == null) {
      throw StateError('Google Drive permission needs to be renewed.');
    }
    return authorization.authClient(scopes: const [scope]);
  }

  static Future<({String? id, String? version})> _snapshotInfo(
    drive.DriveApi api,
  ) async {
    final files = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$fileName' and trashed = false",
      $fields: 'files(id,version),nextPageToken',
      pageSize: 2,
    );
    final items = files.files ?? [];
    if (items.length > 1 || files.nextPageToken != null) {
      throw StateError(
        'Multiple Drive sync files found. Sync stopped to protect your data.',
      );
    }
    if (items.isEmpty) return (id: null, version: null);
    final file = items.single;
    if (file.id == null || file.version == null) {
      throw StateError('Drive sync file version is unavailable.');
    }
    return (id: file.id, version: file.version);
  }

  static Future<int> _mergeSnapshot(
    drive.DriveApi api,
    ({String? id, String? version}) snapshot,
    String passphrase,
  ) async {
    final id = snapshot.id;
    if (id == null) return 0;
    final response = await api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    if (response is! drive.Media) {
      throw const FormatException('Drive returned a non-file response');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
    }
    final decrypted = await CloudSyncEncryption.decrypt(
      utf8.decode(bytes),
      passphrase,
    );
    return FolderSync.absorb(
      BackupService.parseCloud(decrypted),
      applyDeletions: true,
    );
  }

  static Future<void> _uploadSnapshot(
    drive.DriveApi api,
    ({String? id, String? version}) before,
    String passphrase,
  ) async {
    final payload = await CloudSyncEncryption.encrypt(
      BackupService.cloudJson(),
      passphrase,
    );
    final current = await _snapshotInfo(api);
    if (current != before) {
      throw StateError(
        'Drive data changed on another device. Please sync again.',
      );
    }
    final media = drive.Media(
      Stream<List<int>>.value(utf8.encode(payload)),
      utf8.encode(payload).length,
      contentType: 'application/json',
    );
    final file = drive.File()..name = fileName;
    final id = before.id;
    if (id == null) {
      file.parents = ['appDataFolder'];
      await api.files.create(file, uploadMedia: media, $fields: 'id');
    } else {
      await api.files.update(file, id, uploadMedia: media, $fields: 'id');
    }
  }

  static Future<String?> savedPassphrase() =>
      CloudSyncEncryption.savedPassphrase();

  static Future<void> savePassphrase(String passphrase) =>
      CloudSyncEncryption.savePassphrase(passphrase);
}
