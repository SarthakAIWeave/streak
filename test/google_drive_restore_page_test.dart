import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:streak/features/settings/pages/google_drive_page.dart';
import 'package:streak/services/cloud_sync_config.dart';

class CancelledRestorePlatform extends GoogleSignInPlatform {
  @override
  Future<void> init(InitParameters params) async {}

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) async {
    throw const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
  }

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async => const AuthenticationResults(
    user: GoogleSignInUserData(email: 'test@example.com', id: '123'),
    authenticationTokens: AuthenticationTokenData(idToken: 'test'),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'a cancelled silent restore leaves sign-in available without an error',
    (
      tester,
    ) async {
      GoogleSignInPlatform.instance = CancelledRestorePlatform();
      await tester.pumpWidget(const MaterialApp(home: GoogleDrivePage()));
      await tester.pumpAndSettle();

      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.textContaining('Could not restore'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Drive connected'), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
    },
    skip: !CloudSyncConfig.googleDriveConfigured,
  );
}
