import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/services/cloud_sync_config.dart';
import 'package:streak/services/cloud_sync_encryption.dart';
import 'package:streak/services/cloud_sync_envelope.dart';
import 'package:streak/services/google_drive_sync.dart';

import 'support/app_harness.dart';

class _Platform extends GoogleSignInPlatform {
  @override
  Future<void> init(InitParameters params) async {}
  @override
  bool supportsAuthenticate() => true;
  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async => const AuthenticationResults(
    user: GoogleSignInUserData(email: 'test@example.com', id: '123'),
    authenticationTokens: AuthenticationTokenData(idToken: 'token'),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  useEmptyStore();

  test(
    'merges and refreshes UI, then refuses a changed remote snapshot',
    () async {
      GoogleSignInPlatform.instance = _Platform();
      await GoogleDriveSync.initialize();
      await GoogleDriveSync.signIn();
      await LocalStore.writeSetting('driveSyncEnabled', true);
      await LocalStore.writeHabit(testHabit(id: 'local', name: 'Local'));
      final habits = HabitsController();
      addTearDown(habits.dispose);
      final encrypted = await CloudSyncEncryption.encrypt(
        CloudSyncEnvelope.encode({
          'habits': [testHabit(id: 'remote', name: 'Remote').toMap()],
        }),
        'a long passphrase',
      );
      var metadataCalls = 0;
      var uploads = 0;
      var conflict = false;
      var refreshed = 0;
      var activeRequests = 0;
      var maxRequests = 0;
      var editDuringUpload = false;
      GoogleDriveSync.onRemoteMerged = () async {
        await habits.reload();
        refreshed++;
      };
      GoogleDriveSync.clientForTesting = (_) async {
        final client = MockClient((request) async {
          activeRequests++;
          if (activeRequests > maxRequests) maxRequests = activeRequests;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          activeRequests--;
          if (request.url.path.endsWith('/drive/v3/files')) {
            metadataCalls++;
            final version = conflict && metadataCalls.isEven ? '2' : '1';
            return http.Response(
              json.encode({
                'files': [
                  {'id': 'remote-file', 'version': version},
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.method == 'GET') {
            return http.Response(
              encrypted,
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'PATCH') {
            uploads++;
            if (editDuringUpload) {
              editDuringUpload = false;
              await LocalStore.writeHabit(
                testHabit(id: 'late', name: 'Late edit'),
              );
            }
            return http.Response(
              '{"id":"remote-file"}',
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('unexpected request', 500);
        });
        return auth.authenticatedClient(
          client,
          auth.AccessCredentials(
            auth.AccessToken(
              'Bearer',
              'token',
              DateTime.now().toUtc().add(const Duration(hours: 1)),
            ),
            null,
            [GoogleDriveSync.scope],
          ),
        );
      };
      addTearDown(() {
        GoogleDriveSync.stopAutoSync();
        GoogleDriveSync.clientForTesting = null;
        GoogleDriveSync.onRemoteMerged = null;
        GoogleDriveSync.setAccount(null);
      });

      await GoogleDriveSync.sync(passphrase: 'a long passphrase');
      expect(habits.byId('local'), isNotNull);
      expect(habits.byId('remote'), isNotNull);
      expect(refreshed, 1);
      expect(uploads, 1);

      await GoogleDriveSync.sync(passphrase: 'a long passphrase', interactive: false);
      expect(refreshed, 1);
      expect(uploads, 1);

      await expectLater(
        GoogleDriveSync.sync(passphrase: 'wrong passphrase'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      expect(uploads, 1);
      expect(habits.byId('local'), isNotNull);

      conflict = true;
      metadataCalls = 0;
      await expectLater(
        GoogleDriveSync.sync(passphrase: 'a long passphrase'),
        throwsA(isA<StateError>()),
      );
      expect(uploads, 1);
      expect(habits.byId('local'), isNotNull);
      expect(habits.byId('remote'), isNotNull);

      conflict = false;
      await Future.wait([
        GoogleDriveSync.sync(passphrase: 'a long passphrase'),
        GoogleDriveSync.sync(passphrase: 'a long passphrase'),
      ]);
      expect(maxRequests, 1);
      expect(uploads, 3);

      GoogleDriveSync.startAutoSync();
      await LocalStore.writeHabit(testHabit(id: 'changed', name: 'Changed'));
      editDuringUpload = true;
      await GoogleDriveSync.sync(
        passphrase: 'a long passphrase',
        interactive: false,
      );
      await GoogleDriveSync.sync(
        passphrase: 'a long passphrase',
        interactive: false,
      );
      expect(uploads, 5);
      expect(LocalStore.habit('late'), isNotNull);
    },
    skip: CloudSyncConfig.googleDriveConfigured
        ? false
        : 'Run with --dart-define=GOOGLE_WEB_CLIENT_ID=test',
  );
}
