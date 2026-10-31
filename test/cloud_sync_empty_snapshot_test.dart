import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/services/backup_service.dart';
import 'package:streak/services/cloud_sync_encryption.dart';
import 'package:streak/services/cloud_sync_envelope.dart';
import 'package:streak/services/folder_sync.dart';

import 'support/app_harness.dart';

void main() {
  useEmptyStore();

  test('an empty encrypted cloud snapshot preserves the local habit', () async {
    await LocalStore.writeHabit(testHabit(id: 'one', name: 'Read'));
    final snapshot = CloudSyncEnvelope.encode({'habits': <Object>[]});
    final encrypted = await CloudSyncEncryption.encrypt(
      snapshot,
      'a long passphrase',
    );
    final decrypted = await CloudSyncEncryption.decrypt(
      encrypted,
      'a long passphrase',
    );
    final merged = await FolderSync.absorb(BackupService.parseCloud(decrypted));

    expect(merged, 0);
    expect(LocalStore.habit('one')?.name, 'Read');
    final upload = CloudSyncEnvelope.decode(BackupService.cloudJson());
    expect(upload['habits'], hasLength(1));
  });

  test('malformed cloud snapshots do not pass as empty', () {
    expect(
      () => BackupService.parseCloud(
        CloudSyncEnvelope.encode({
          'habits': [42],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => BackupService.parseCloud(
        CloudSyncEnvelope.encode({'habits': [], 'todos': 'invalid'}),
      ),
      throwsFormatException,
    );
    expect(
      () => BackupService.parse(json.encode({'habits': []})),
      throwsException,
    );
  });
}
