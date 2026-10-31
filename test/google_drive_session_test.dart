import 'package:flutter_test/flutter_test.dart';
// The platform interface is used to simulate the native Google sign-in plugin.
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:streak/services/cloud_sync_config.dart';
import 'package:streak/services/google_drive_sync.dart';

class FakeGoogleSignIn extends GoogleSignInPlatform {
  int initializations = 0;
  int restores = 0;

  @override
  Future<void> init(InitParameters params) async => initializations++;

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async {
    restores++;
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
  test(
    'restores a session once and keeps an explicit sign-out',
    () async {
      final platform = FakeGoogleSignIn();
      GoogleSignInPlatform.instance = platform;
      await Future.wait([
        GoogleDriveSync.restoreSession(),
        GoogleDriveSync.restoreSession(),
      ]);
      expect(platform.initializations, 1);
      expect(platform.restores, 1);
      expect(GoogleDriveSync.account?.email, 'test@example.com');
      await GoogleDriveSync.signOut();
      await GoogleDriveSync.restoreSession();
      expect(GoogleDriveSync.account, isNull);
      expect(platform.restores, 1);
    },
    skip: CloudSyncConfig.googleDriveConfigured
        ? false
        : 'Run with --dart-define=GOOGLE_WEB_CLIENT_ID=test',
  );
}
