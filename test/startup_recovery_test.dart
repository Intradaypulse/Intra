import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/main.dart';
import 'package:pdfmate/settings_store.dart';

class FailingSettings extends AppSettingsStore {
  bool fail = true;
  @override
  Future<ThemeMode> loadThemeMode() async {
    if (fail) throw StateError('preferences unavailable');
    return ThemeMode.system;
  }
  @override
  Future<bool> loadAutoSaveDownloads() async => true;
  @override
  Future<bool> isOnboardingComplete() async => false;
}

void main() {
  testWidgets('startup preferences failure offers Retry and recovers', (tester) async {
    final settings = FailingSettings();
    await tester.pumpWidget(PDFMateApp(settingsStore: settings));
    await tester.pump();
    expect(find.text('Could not load settings.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    settings.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Scan documents cleanly'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
