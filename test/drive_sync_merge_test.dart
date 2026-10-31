import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/services/backup_service.dart';
import 'package:streak/services/cloud_sync_envelope.dart';
import 'package:streak/services/folder_sync.dart';

import 'support/app_harness.dart';

void main() {
  useEmptyStore();

  test('Drive tracks local edits and deletions without folder sync', () async {
    await LocalStore.writeSetting('driveSyncEnabled', true);
    await LocalStore.writeHabit(testHabit(id: 'habit', name: 'Read'));
    expect(LocalStore.changedAt('habit'), isNotNull);
    await LocalStore.removeHabit('habit');
    expect(LocalStore.deletedAt('habit'), isNotNull);
  });

  test(
    'tracks edits while Drive is disconnected after being configured',
    () async {
      await LocalStore.writeSetting('driveSyncTracking', true);
      await LocalStore.writeSetting('driveSyncEnabled', false);
      await LocalStore.writeHabit(testHabit(id: 'offline', name: 'Offline'));
      expect(LocalStore.changedAt('offline'), isNotNull);
    },
  );

  test(
    'Drive applies newer remote deletion without folder sync enabled',
    () async {
      await LocalStore.writeSetting('driveSyncEnabled', true);
      await LocalStore.writeHabit(testHabit(id: 'habit', name: 'Read'));
      final stamp = LocalStore.changedAt('habit')! + 1;
      final raw = CloudSyncEnvelope.encode({
        'habits': [],
        'deleted': {'habit': stamp},
      });
      final result = await FolderSync.absorb(
        BackupService.parseCloud(raw),
        applyDeletions: true,
      );
      expect(result, 1);
      expect(LocalStore.habit('habit'), isNull);
      expect(json.decode(BackupService.cloudJson())['deleted']['habit'], stamp);
    },
  );

  test('concurrent incoming snapshots merge in order', () async {
    final firstStamp = DateTime.now().millisecondsSinceEpoch + 1000;
    BackupData snapshot(String name, int stamp) => BackupService.parseCloud(
      CloudSyncEnvelope.encode({
        'habits': [testHabit(id: 'shared', name: name).toMap()],
        'changes': {'shared': stamp},
      }),
    );
    await Future.wait([
      FolderSync.absorb(snapshot('First', firstStamp), applyDeletions: true),
      FolderSync.absorb(
        snapshot('Second', firstStamp + 1),
        applyDeletions: true,
      ),
    ]);
    expect(LocalStore.habit('shared')?.name, 'Second');
    expect(LocalStore.changedAt('shared'), firstStamp + 1);
  });
}
