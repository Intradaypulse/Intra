# ScanLumo production release checklist

PDFMate must never store private production credentials in Dart source or committed workflow files. AdMob app/ad-unit identifiers are public SDK configuration, not account credentials.
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

### Supplied ScanLumo identifiers
The owner supplied these public IDs on 4 October 2026:
- App: `ca-app-pub-4375542757188713~4072508265`
- Banner (`scan`): `ca-app-pub-4375542757188713/3974279220`
- Interstitial (`scan Interstitial`): `ca-app-pub-4375542757188713/8696122864`
- Rewarded: `ca-app-pub-4375542757188713/3609559552`
- App-Open: `ca-app-pub-4375542757188713/9984144645`

Production workflow and readiness checks use these as fallbacks; matching repository Secrets or Variables override them. All five required AdMob identifiers have been supplied. Firebase, signing and public operator/privacy configuration remain separate requirements. Supplying identifiers does not verify AdMob readiness or ad serving. Beta APKs retain test ad configuration. The app display name is ScanLumo. Its established package identity remains `com.pdfmateapp.pdfmate`, and existing storage folders/keys and signature backup format are retained for compatibility.


## Firebase
- `FIREBASE_API_KEY`
- `FIREBASE_APP_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_STORAGE_BUCKET`

### Supplied Firebase project
`config/google-services.json` is the owner-provided Android client configuration for project `scanlumo`, registered for `com.pdfmateapp.pdfmate`. It contains client SDK identifiers, not a service-account private key. Release/preflight environment values use these supplied values as fallbacks, with repository Secrets or Variables taking precedence. The release workflow generates the matching native configuration and passes the same values to Dart.

Analytics, Crashlytics and Remote Config code are present, but receiving live events is not verified by configuration alone. Beta artifacts continue their existing test-ad/no-live-Firebase setup. Production activation still requires established signing and public operator/privacy configuration. No Firebase Admin SDK credential or remote admin-panel publishing access has been granted.

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
3. Run **Build ScanLumo Release AAB** from GitHub Actions.
4. The workflow validates every required secret and the keystore alias.
5. It builds the signed Play AAB and per-ABI release APKs.
6. It verifies the AAB with `jarsigner` and APKs with `apksigner`.
7. Upload `ScanLumo-release.aab` to the intended Play Console testing track before production rollout.

Do not paste keystore passwords or private key material into source code, issues, pull requests, or chat messages.

## app-ads.txt
Before production launch, publish the exact `app-ads.txt` line supplied by the AdMob account on the developer website listed in Google Play. Do not publish a sample publisher ID.

## Runtime behavior
Debug/beta builds use Google's test ad units when production IDs are absent. Signed production builds fail fast if any required AdMob, Firebase, or signing secret is missing, so a release cannot silently ship with test monetization or disabled telemetry.

## Device and upgrade validation
Keep the established signing keys. Export signature backups and shared PDF copies before testing an installation change. Verify an upgrade from the previously distributed release using the intended distribution channel; fresh installs and reinstalling the same APK do not prove cross-version data preservation. Physical OEM QA and a real mixed-language document corpus remain separate release gates in DEVICE_QA.md.
