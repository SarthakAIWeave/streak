import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
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

  static GoogleSignInAccount? get account => _account;

  static void setAccount(GoogleSignInAccount? account) {
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
        if (restored != null) setAccount(restored);
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
    _account = account;
    return account;
  }

  static Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    stopAutoSync();
    _account = null;
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
    LocalStore.removeChangeListener(_changed);
    _autoTimer?.cancel();
    _periodicTimer?.cancel();
    _autoTimer = null;
    _periodicTimer = null;
  }

  static void _changed() {
    if (!_autoStarted || _account == null) return;
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(seconds: 15), _runAuto);
  }

  static Future<void> _runAuto() async {
    if (_autoBusy || _account == null) return;
    final passphrase = await savedPassphrase();
    if (passphrase == null) return;
    _autoBusy = true;
    try {
      await pullAndMerge(passphrase: passphrase);
      await upload(passphrase: passphrase);
    } catch (_) {
      // Manual sync remains available when the network returns.
    } finally {
      _autoBusy = false;
    }
  }

  static Future<auth.AuthClient?> _client() async {
    final user = _account;
    if (user == null) return null;
    var authorization = await user.authorizationClient.authorizationForScopes(
      const [scope],
    );
    authorization ??= await user.authorizationClient.authorizeScopes(
      const [scope],
    );
    return authorization.authClient(scopes: const [scope]);
  }

  static Future<drive.DriveApi?> _api() async {
    final client = await _client();
    return client == null ? null : drive.DriveApi(client);
  }

  static Future<String?> download() async {
    final api = await _api();
    if (api == null) return null;
    final files = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$fileName' and trashed = false",
      $fields: 'files(id,modifiedTime)',
      pageSize: 1,
    );
    final id = files.files?.isNotEmpty == true ? files.files!.first.id : null;
    if (id == null) return null;
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
    return utf8.decode(bytes);
  }

  static Future<void> upload({required String passphrase}) async {
    final api = await _api();
    if (api == null) throw StateError('Google Drive is not connected.');
    final payload = await CloudSyncEncryption.encrypt(
      BackupService.cloudJson(),
      passphrase,
    );
    final existing = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$fileName' and trashed = false",
      $fields: 'files(id)',
      pageSize: 1,
    );
    final media = drive.Media(
      Stream<List<int>>.value(utf8.encode(payload)),
      utf8.encode(payload).length,
      contentType: 'application/json',
    );
    final file = drive.File()..name = fileName;
    final id = existing.files?.isNotEmpty == true
        ? existing.files!.first.id
        : null;
    if (id == null) {
      file.parents = ['appDataFolder'];
      await api.files.create(file, uploadMedia: media, $fields: 'id');
    } else {
      await api.files.update(file, id, uploadMedia: media, $fields: 'id');
    }
  }

  static Future<int> pullAndMerge({required String passphrase}) async {
    final raw = await download();
    if (raw == null) return 0;
    final decrypted = await CloudSyncEncryption.decrypt(raw, passphrase);
    return FolderSync.absorb(BackupService.parseCloud(decrypted));
  }

  static Future<String?> savedPassphrase() =>
      CloudSyncEncryption.savedPassphrase();

  static Future<void> savePassphrase(String passphrase) =>
      CloudSyncEncryption.savePassphrase(passphrase);
}
