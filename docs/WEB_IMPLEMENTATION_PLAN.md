# Web and Google Drive implementation plan

This work is intentionally split into milestones so the Android app remains
usable after each change.

## 1. Web build foundation

- Add the Flutter web target and keep the existing `StreakApp` theme,
  navigation, responsive shell, and localization.
- Isolate `dart:io`, method-channel, notification, widget, biometric, and
  desktop-window code behind platform-safe boundaries.
- Use browser storage for the web-local database and browser-compatible file
  import/export paths.
- Make unsupported device-only features disappear or become harmless no-ops
  on web; do not change Android behavior.
- Verify with `flutter analyze`, web compilation, and the existing tests.

## 2. Sync data contract

- Reuse the existing backup format and merge logic in `auto_sync.dart` and
  `folder_sync.dart`.
- Define a versioned cloud envelope without uploading the live Hive database.
- Include device identity, change stamps, deletions, and attachments safely.
- Add migration and recovery behavior before adding any network code.

## 3. Google Drive authentication

- Add Google sign-in only when the user explicitly enables sync.
- Request the least-privilege Drive scope needed for the app's sync folder.
- Store refresh credentials using the platform's secure storage facilities;
  never put them in the backup file.
- Keep local-only use possible without a Google account.

## 4. Google Drive sync

- Upload/download the encrypted, versioned sync envelope.
- Reuse the existing merge engine for multi-device changes.
- Make sync retryable and offline-first, with clear last-sync/error state.

## 5. Web parity and verification

- Match Android typography, colors, spacing, navigation, and responsive layout.
- Test browser refresh, offline mode, sign-in/out, backup recovery, and
  simultaneous edits.
- Test Android 9 through current Android releases for regressions.

## Current milestone

Milestone 1 is complete enough for the local web build to compile and run.

## Drive milestone in progress

- Keep the existing backup JSON and merge engine as the sync data model.
- Wrap cloud files in a small versioned envelope so future migrations can
  reject unknown formats safely.
- Use a Drive `appDataFolder` file with the least-privilege `drive.appdata`
  scope; do not upload the live database or device-only files.
- Add authentication and the Drive transport only after this contract passes
  local validation.
