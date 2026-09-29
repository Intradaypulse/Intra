import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/settings_screen.dart';

void main() {
  testWidgets('privacy policy opens offline from Settings', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(
      themeMode: ThemeMode.system,
      autoSaveDownloads: false,
      onThemeChanged: (_) async {},
      onAutoSaveChanged: (_) async {},
    )));
    final link = find.byKey(const ValueKey('settings_privacy_policy'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('Downloads and Gallery exports'), findsOneWidget);
  });
}
