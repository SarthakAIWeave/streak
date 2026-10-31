import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/services/cloud_sync_config.dart';
import 'package:streak/services/google_drive_sync.dart';

import 'support/app_harness.dart';

class _RestorePlatform extends GoogleSignInPlatform {
  int attempts = 0;

  @override
  Future<void> init(InitParameters params) async {}
  @override
  bool supportsAuthenticate() => true;
  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async {
    attempts++;
    return const AuthenticationResults(
      user: GoogleSignInUserData(email: 'test@example.com', id: '123'),
      authenticationTokens: AuthenticationTokenData(idToken: 'test'),
    );
  }

  @override
  Future<void> signOut(SignOutParams params) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  useEmptyStore();
  test(
    'resumes a configured account and respects explicit disconnect',
    () async {
      const storage = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            storage,
            (call) async => call.method == 'read' ? 'a long passphrase' : null,
          );
      final platform = _RestorePlatform();
      GoogleSignInPlatform.instance = platform;
      GoogleDriveSync.clientForTesting = (_) async =>
          throw StateError('offline');
      addTearDown(() {
        GoogleDriveSync.stopAutoSync();
        GoogleDriveSync.clientForTesting = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(storage, null);
      });

      await GoogleDriveSync.resume();
      expect(platform.attempts, 1);
      expect(GoogleDriveSync.account?.email, 'test@example.com');
      expect(LocalStore.setting('driveSyncEnabled', false), isTrue);
      expect(LocalStore.setting('driveSyncTracking', false), isTrue);
      await GoogleDriveSync.signOut();
      await GoogleDriveSync.resume();
      expect(platform.attempts, 1);
      expect(GoogleDriveSync.account, isNull);
      expect(LocalStore.setting('driveSyncEnabled', true), isFalse);
    },
    skip: CloudSyncConfig.googleDriveConfigured
        ? false
        : 'Run with --dart-define=GOOGLE_WEB_CLIENT_ID=test',
  );
}
