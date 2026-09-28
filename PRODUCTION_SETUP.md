# PDFMate production release checklist

PDFMate must never store production credentials in Dart source or committed workflow files.
Configure these values under **GitHub repository → Settings → Secrets and variables → Actions**.

## Android signing
- `ANDROID_KEYSTORE_BASE64` — base64 of the Play upload keystore
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

## AdMob
- `ADMOB_APP_ID`
- `ADMOB_BANNER_ID`
- `ADMOB_INTERSTITIAL_ID`
- `ADMOB_REWARDED_ID`
- `ADMOB_APP_OPEN_ID`

The production workflow rejects Google's sample/test publisher IDs.

## Firebase
- `FIREBASE_API_KEY`
- `FIREBASE_APP_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_STORAGE_BUCKET`

## Release process
1. Merge a CI-green PDFMate change to `main`.
2. Confirm the normal CI release-candidate APK and AAB pass.
3. Run **Build PDFMate Release AAB** from GitHub Actions.
4. The workflow validates every required secret and the keystore alias.
5. It builds the signed Play AAB and per-ABI release APKs.
6. It verifies the AAB with `jarsigner` and APKs with `apksigner`.
7. Upload `PDFMate-release.aab` to the intended Play Console testing track before production rollout.

Do not paste keystore passwords or private key material into source code, issues, pull requests, or chat messages.
