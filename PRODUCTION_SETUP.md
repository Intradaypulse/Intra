# PDFMate production release checklist

PDFMate must never store production credentials in Dart source or committed workflow files.
Configure these values under **GitHub repository → Settings → Secrets and variables → Actions**.

## Android signing
- `ANDROID_KEYSTORE_BASE64` — base64 of the Play upload keystore
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

## AdMob
- `ADMOB_APP_ID` — `ca-app-pub-...~...`
- `ADMOB_BANNER_ID` — `ca-app-pub-.../...`
- `ADMOB_INTERSTITIAL_ID` — `ca-app-pub-.../...`
- `ADMOB_REWARDED_ID` — `ca-app-pub-.../...`
- `ADMOB_APP_OPEN_ID` — `ca-app-pub-.../...`

The production workflow rejects Google's sample/test publisher IDs and malformed AdMob IDs.

## Firebase
- `FIREBASE_API_KEY`
- `FIREBASE_APP_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_STORAGE_BUCKET`

## Public repository variables
Set these under **Settings → Secrets and variables → Actions → Variables**:
- `ANDROID_UPLOAD_CERT_SHA256` — SHA-256 of the DER certificate for the existing Play upload key. The release rejects a different key instead of silently changing the signing identity. Play App Signing may use a separate app signing certificate; use Play testing tracks to verify updates of Play-installed apps.
- `PDFMATE_OPERATOR_NAME` — responsible operator/company.
- `PDFMATE_PRIVACY_EMAIL` — working privacy contact.
- `PDFMATE_PRIVACY_URL` — public HTTPS policy address.

The beta workflow reports configured/missing/invalid field names without printing values. This is configuration preflight, not evidence that ads serve or Firebase receives events. Production validation requires all fields and embeds the supplied public details in the in-app notice. Publish the matching public policy and account-provided app-ads.txt on the real developer domain; placeholder details must not be used.

## Release process
1. Merge a CI-green PDFMate change to `main`.
2. Confirm the normal CI release-candidate APK and AAB pass.
3. Run **Build PDFMate Release AAB** from GitHub Actions.
4. The workflow validates every required secret and the keystore alias.
5. It builds the signed Play AAB and per-ABI release APKs.
6. It verifies the AAB with `jarsigner` and APKs with `apksigner`.
7. Upload `PDFMate-release.aab` to the intended Play Console testing track before production rollout.

Do not paste keystore passwords or private key material into source code, issues, pull requests, or chat messages.

## app-ads.txt
Before production launch, publish the exact `app-ads.txt` line supplied by the AdMob account on the developer website listed in Google Play. Do not publish a sample publisher ID.

## Runtime behavior
Debug/beta builds use Google's test ad units when production IDs are absent. Signed production builds fail fast if any required AdMob, Firebase, or signing secret is missing, so a release cannot silently ship with test monetization or disabled telemetry.

## Device and upgrade validation
Keep the established signing keys. Export signature backups and shared PDF copies before testing an installation change. Verify an upgrade from the previously distributed release using the intended distribution channel; fresh installs and reinstalling the same APK do not prove cross-version data preservation. Physical OEM QA and a real mixed-language document corpus remain separate release gates in DEVICE_QA.md.
