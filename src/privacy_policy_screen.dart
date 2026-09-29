import 'package:flutter/material.dart';

/// Keep this notice aligned with the SDKs and actual application behavior.
const privacyPolicyText = '''PDFMate privacy notice
Updated: 30 September 2026

Documents and OCR
PDF processing, camera scanning and supported OCR run on your device. PDFMate's document tools do not upload document contents to a PDFMate server. Documents you explicitly share are passed to the application you select; that application's privacy practices then apply.

Storage and deletion
Created PDFs remain in app storage until deleted or app data is cleared. Downloads and Gallery exports are additional copies: remove those separately using Android Files or Gallery. Temporary working files are used during conversion. Cleanup is attempted when work ends and at startup; interruptions can leave temporary files until cleanup runs. Deletion does not guarantee forensic erasure from flash storage or backups.

Camera and permissions
Camera access is used to scan documents. The system picker grants access to selected files. Older Android versions may require storage permission to export to shared storage. You can change permissions in Android Settings.

Advertising
PDFMate uses Google Mobile Ads and Google's consent platform. Advertising services may process device identifiers, IP address, ad interactions and diagnostic information. Available consent settings are under Settings > Privacy choices. Test builds use test ads; a test ad does not mean all network communication is disabled.

Analytics and diagnostics
When configured and enabled, Firebase Analytics, Crashlytics and Remote Config process usage events, crash information, device/app information and configuration requests. Diagnostic error messages can contain file names or paths. Document contents are not intentionally sent as analytics events. The Settings screen shows whether Firebase initialized.

Third-party information
Google privacy information: https://policies.google.com/privacy
Firebase privacy information: https://firebase.google.com/support/privacy

This notice describes the current beta. A production release must also identify the responsible operator, provide a working privacy contact and publish this policy at a public HTTPS address. Those operator details have not yet been supplied for this beta.
''';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy policy')),
    body: const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: SelectableText(privacyPolicyText),
      ),
    ),
  );
}
