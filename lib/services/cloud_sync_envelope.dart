import 'dart:convert';

/// The small, stable wrapper used by cloud transports.
///
/// The backup payload stays in its existing shape so BackupService.parse and
/// FolderSync can continue to handle merges and older local backups.
class CloudSyncEnvelope {
  const CloudSyncEnvelope._();

  static const format = 'streak-drive-sync';
  static const version = 1;

  static String encode(Map<String, Object?> payload) => json.encode({
    'syncFormat': format,
    'syncVersion': version,
    ...payload,
  });

  static Map<String, dynamic> decode(String raw) {
    final decoded = json.decode(raw);
    if (decoded is! Map || decoded['syncFormat'] != format) {
      throw const FormatException('Unrecognised Streak cloud sync file');
    }
    if (decoded['syncVersion'] != version) {
      throw const FormatException('Unsupported Streak cloud sync version');
    }
    if (decoded['habits'] is! List) {
      throw const FormatException('Streak cloud sync data is incomplete');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
