import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:streak/services/cloud_sync_encryption.dart';

void main() {
  test('encrypted cloud payload round-trips and rejects a wrong passphrase', () async {
    const payload = '{"syncFormat":"streak-drive-sync","habits":[]}';
    final encrypted = await CloudSyncEncryption.encrypt(payload, 'correct horse battery staple');

    expect(await CloudSyncEncryption.decrypt(
      encrypted,
      'correct horse battery staple',
    ), payload);
    expect(
      () => CloudSyncEncryption.decrypt(encrypted, 'wrong passphrase'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
