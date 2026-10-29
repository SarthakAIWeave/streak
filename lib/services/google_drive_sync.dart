import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:streak/services/backup_service.dart';
import 'package:streak/services/cloud_sync_config.dart';
import 'package:streak/services/cloud_sync_envelope.dart';
import 'package:streak/services/folder_sync.dart';

class GoogleDriveSync {
  const GoogleDriveSync._();

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const fileName = 'streak-sync.json';

  static Future<void> initialize() async {
    if (!kIsWeb && !GoogleSignIn.instance.supportsAuthenticate()) return;
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? CloudSyncConfig.googleWebClientId : null,
      serverClientId: kIsWeb ? null : CloudSyncConfig.googleWebClientId,
    );
  }

  static Future<GoogleSignInAccount?> signIn() async {
    await initialize();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw StateError('This platform needs the Google Sign-In button.');
    }
    return GoogleSignIn.instance.authenticate();
  }

  static Future<void> signOut() => GoogleSignIn.instance.signOut();

  static Future<auth.AuthClient?> _client() async {
    final user = GoogleSignIn.instance.currentUser;
    if (user == null) return null;
    final authorization = await user.authorizationClient.authorizeScopes(const [
      scope,
    ]);
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

  static Future<void> upload() async {
    final api = await _api();
    if (api == null) throw StateError('Google Drive is not connected.');
    final payload = BackupService.cloudJson();
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

  static Future<int> pullAndMerge() async {
    final raw = await download();
    if (raw == null) return 0;
    final decoded = CloudSyncEnvelope.decode(raw);
    return FolderSync.absorb(BackupService.parse(json.encode(decoded)));
  }
}
