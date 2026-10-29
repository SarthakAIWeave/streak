import 'package:flutter_test/flutter_test.dart';
import 'package:streak/services/cloud_sync_envelope.dart';

void main() {
  test('round trips a versioned cloud payload', () {
    final raw = CloudSyncEnvelope.encode({
      'habits': <Object?>[],
      'device': 'test-device',
    });

    final decoded = CloudSyncEnvelope.decode(raw);
    expect(decoded['syncFormat'], CloudSyncEnvelope.format);
    expect(decoded['syncVersion'], CloudSyncEnvelope.version);
    expect(decoded['device'], 'test-device');
  });

  test('rejects a payload from another format', () {
    expect(
      () => CloudSyncEnvelope.decode('{"habits":[]}'),
      throwsFormatException,
    );
  });
}
