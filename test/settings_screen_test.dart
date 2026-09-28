import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/settings_screen.dart';

void main() {
  testWidgets('settings exposes production diagnostics and file safety toggle',
      (tester) async {
    bool? autoSaveValue;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          themeMode: ThemeMode.system,
          autoSaveDownloads: false,
          onThemeChanged: (_) async {},
          onAutoSaveChanged: (value) async => autoSaveValue = value,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('settings_ad_mode')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings_firebase_status')),
      findsOneWidget,
    );
    expect(find.text('Auto-save a copy to Downloads'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(autoSaveValue, isTrue);
  });
}
