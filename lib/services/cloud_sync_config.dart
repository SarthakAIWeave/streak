/// Build-time configuration for optional cloud sync.
///
/// Credentials stay outside the repository and are supplied by the host app
/// or deployment command. The empty default keeps Streak local-only.
class CloudSyncConfig {
  const CloudSyncConfig._();

  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  static bool get googleDriveConfigured => googleWebClientId.isNotEmpty;
}
