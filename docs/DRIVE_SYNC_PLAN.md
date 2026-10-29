# Google Drive sync implementation plan

## Goal

Use Google Drive as an optional cloud copy while keeping Streak useful and
private when offline or signed out. The Android app and web app will share the
same versioned Streak payload and merge rules.

## Sequence

1. **Contract — done**

   The existing backup payload is wrapped in `streak-drive-sync` version 1.
   Unknown formats are rejected before they reach the merge engine.

2. **Google authorization — next**

   Add Google Sign-In only when the user enables Drive sync. Web builds will
   receive `GOOGLE_WEB_CLIENT_ID` at build/deploy time; no client secret goes
   in this repository or in the browser bundle.

3. **Drive file adapter**

   Store one sync file in Drive's hidden `appDataFolder` using the narrow
   `drive.appdata` scope. Uploads will use revision/modified-time checks and
   retry without replacing a newer remote file.

4. **Merge and recovery**

   Decode the envelope, reuse `FolderSync.absorb`, and retain the local copy
   until a successful remote write is confirmed. A malformed or unsupported
   remote file must never overwrite local data.

5. **Android parity**

   Use the Android Google client ID and the same Drive file/format. Keep the
   feature optional so Android 9–16 can continue in fully offline mode.

## Security requirements

- **Client IDs are not passwords.** Web and Android OAuth client IDs are
  identifiers and may appear in the shipped app. Client secrets, refresh
  tokens, service-account keys, and private signing keys must never be put in
  Dart code, `web/index.html`, Git, or a downloadable build.
- **Web tokens stay in memory.** The web build will use Google's browser OAuth
  flow, keep short-lived access tokens out of localStorage/IndexedDB, and
  discard them on sign-out or expiry. The web app will not store a refresh
  token in the browser.
- **Use HTTPS and exact origins.** Production OAuth origins will be exact
  `https://...` origins owned by the deployment. No wildcard domains,
  shortened URLs, or untrusted preview domains will be registered.
- **Request only `drive.appdata`.** This keeps the sync file in Drive's hidden
  application-data area and avoids access to the user's normal Drive files.
  A hidden app-data file is not the same thing as end-to-end encryption.
- **Encrypt before upload for strong privacy.** The implementation uses
  AES-GCM with a PBKDF2-derived key from the user's sync passphrase. The
  passphrase is kept in the platform secure store, is never uploaded, and
  cannot be recovered by Google if lost.
- **Treat remote data as untrusted.** Validate format/version/size before
  parsing, merge only through the existing engine, keep a local recovery copy,
  and never replace local data after a failed or partial download.
- **Add revocation and deletion controls.** Sign-out will clear local tokens;
  the settings screen will provide “Disconnect Drive” and delete the app's
  cloud file after explicit confirmation.
- **Add browser hardening at deployment.** Use a restrictive Content-Security-
  Policy, prevent framing, set `Referrer-Policy: no-referrer`, and do not load
  arbitrary third-party scripts. The Google Identity Services script will be
  the only intentional external authentication dependency.

## Required Google setup before step 2 can be exercised

- A Google Cloud project with Drive API enabled.
- A web OAuth client with the production HTTPS origin registered.
- An Android OAuth client with the app package and signing certificate.
- Consent-screen configuration for the selected Drive scope.
- A public homepage, privacy policy, and support contact for friends and other
  users.

## Exact Google Cloud setup

Perform these steps in [Google Cloud Console](https://console.cloud.google.com/).

### 1. Create and select a project

1. Open the project selector and choose **New Project**.
2. Give it a clear name such as `Streak Sync`.
3. Select that project before doing the remaining steps.

### 2. Enable the Drive API

1. Open **APIs & Services → Library**.
2. Search for **Google Drive API**.
3. Open it and click **Enable**.

Do not create a service account for this app. A service account would be the
wrong trust model for personal user Drive data.

### 3. Configure the OAuth consent screen for public users

1. Open **Google Auth Platform → Branding** (or **APIs & Services → OAuth
   consent screen**, depending on the Console layout).
2. Choose **External**. This is required for friends and ordinary users who
   are outside your own Google Workspace organization.
3. Enter the app name, support email, developer contact email, and the real
   homepage/privacy-policy URLs when preparing production hosting.
4. In **Data access → Scopes**, add only:

   `https://www.googleapis.com/auth/drive.appdata`

5. While the app is in testing, add only your own accounts and invited testers
   under **Test users**.
6. Keep the publishing status in **Testing** during development. Testing mode
   is not the public release path: Google documents a 100-user cap for
   unverified apps using sensitive/restricted scopes, and testing-mode
   authorizations may expire. Do not use Testing as the way to distribute the
   finished app.
7. Before telling friends to use the app, submit the consent screen for the
   required Google verification/brand review and publish it to **In
   production** after approval.

`drive.appdata` is a non-sensitive scope, so the full sensitive/restricted
scope review should not normally be needed for this design. Google can still
require brand verification for the public app name/logo and can require more
review if we later add broader scopes. Keep the scope list minimal so the app
remains easy to approve. [Google OAuth verification guidance](https://support.google.com/cloud/answer/13463073)

### 4. Create the web OAuth client

1. Open **Google Auth Platform → Clients → Create client**.
2. Choose **Web application**.
3. Add these development origins:

   - `http://localhost:8765`
   - `http://127.0.0.1:8765`

4. After choosing the production domain, add only its exact origin, for
   example `https://streak.example.com`.
5. Do not add `*`, URL shorteners, random preview hosts, or domains you do not
   own.
6. Copy the **Client ID** only. Never copy a client secret into this app.

For the browser token flow, authorized JavaScript origins are the important
setting. If we later introduce a backend authorization-code flow, we will add
one exact HTTPS redirect URI for that backend; it will not be placed in the
Flutter client.

### 5. Create Android OAuth clients

1. Find the Android package name in the app's Android configuration.
2. Obtain the debug SHA-1 with the Android Gradle signing report.
3. Obtain the release SHA-1 from the release keystore or Google Play Console
   **Release → Setup → App integrity** if Play App Signing is enabled.
4. In **Google Auth Platform → Clients → Create client**, choose **Android**.
5. Create separate clients for debug and release/Play signing where needed.
6. Enter the exact package name and matching SHA-1 for each client.

For this repository the Android package/application ID is `com.streak.app`.
On Windows, the usual local debug certificate can be inspected with:

```powershell
keytool -list -v -alias androiddebugkey `
  -keystore "$env:USERPROFILE\.android\debug.keystore" `
  -storepass android -keypass android
```

Copy the `SHA1` value into the Android client. For release builds, use the
SHA-1 from the real release keystore; for a Play-distributed build, use the
Play App Signing SHA-1 instead of the local upload-key SHA-1.

The Android client ID is also not a secret. The signing private key and any
keystore passwords are secrets and must remain outside Git and outside the
app bundle.

Never copy the downloaded `client_secret_*.json` file into this repository or
upload it to Vercel. This browser-only app needs the public client ID, not the
JSON file or its client secret.

### 6. Configure the app without publishing secrets

For the web build, provide only the public client ID at build time:

```text
flutter build web --dart-define=GOOGLE_WEB_CLIENT_ID=your-client-id.apps.googleusercontent.com
```

For Android, configure the public Android client ID through the normal Google
Sign-In setup. Never add a client secret, service-account JSON file, refresh
token, or private key to this repository.

### 7. Make the app free for ordinary users

1. Do not require a paid subscription or a developer API key from users.
2. Do not ask users to create their own Google Cloud projects or OAuth
   credentials. Everyone uses the app's verified OAuth clients.
3. Make clear that the app itself is free, while each user's Google account
   remains subject to Google's Drive storage limits and service quotas.
4. Keep Drive sync optional. Users can use the app offline without signing in.
5. Provide an in-app privacy policy, support contact, **Disconnect Drive**,
   and **Delete my synced data** action.

### 8. Before public production release

1. Deploy only over HTTPS.
2. Register the final production origin in the web client.
3. Confirm the consent screen names the real app and links to the real privacy
   policy.
4. Test sign-in, token expiry, sign-out, revoked access, malformed cloud data,
   and “Disconnect Drive” on both web and Android.
5. Test with a second Google account that is not an owner/test account.
6. Confirm the app works for users in Testing and then after publishing to
   Production.
7. Restrict deployment secrets and repository access; rotate any credential
   immediately if it is ever committed or exposed.

### 9. Public-use operating checklist

- Monitor Drive API quota and errors in **APIs & Services → Metrics**.
- Use exponential backoff and avoid syncing on every keystroke.
- Never collect or store users' Google passwords.
- Do not use a service account to access users' Drives.
- Keep a clear privacy policy describing what is stored, why it is stored,
  encryption, retention, deletion, and how users disconnect access.
- If the app later requests sensitive or restricted scopes, stop and repeat the
  Google verification/security review before releasing that version.

Until those values exist, the app deliberately remains local-only; it does
not make anonymous Drive requests or ship placeholder credentials.
