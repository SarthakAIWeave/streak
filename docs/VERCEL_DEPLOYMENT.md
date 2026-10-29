# Vercel deployment

This repository is configured for Vercel with `vercel.json`. Vercel builds
Flutter web from a pinned Flutter version and serves `build/web` as a static
site with SPA fallback routing.

## Vercel dashboard

1. Create a new Vercel project from the GitHub repository.
2. Leave the framework preset as **Other**.
3. Keep the build command from `vercel.json`.
4. Keep the output directory from `vercel.json`.
5. Add this environment variable for Preview and Production:

   `GOOGLE_WEB_CLIENT_ID` = the public web OAuth client ID

6. Deploy once using the temporary Vercel URL.
7. Add the final HTTPS domain to Google OAuth **Authorized JavaScript
   origins** before enabling Drive sync for public users.

The client ID is not a password. Never add a Google client secret, refresh
token, service-account JSON, or private key as a Vercel environment variable
for this browser-only app.

## Local verification

The same app can be built locally with:

```text
flutter build web --release --dart-define=GOOGLE_WEB_CLIENT_ID=your-client-id.apps.googleusercontent.com
```

The generated `build/web` directory is the deployable static site.
