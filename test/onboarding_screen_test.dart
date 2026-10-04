import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/onboarding_screen.dart';

void main() {
  testWidgets('Skip locks finishing and reports failure before retry', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onFinished: () {
      calls++;
      return calls == 1 ? pending.future : Future<void>.value();
    })));
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Skip')).onPressed, isNull);
    expect(calls, 1);
    pending.completeError(StateError('disk failed'));
    await tester.pump();
    expect(find.text('Could not save onboarding. Please retry.'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding completes from Skip', (tester) async {
    var finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onFinished: () async => finished = true,
        ),
      ),
    );

    expect(find.text('Scan documents cleanly'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(finished, isTrue);
  });

  testWidgets('onboarding can advance through all pages', (tester) async {
    var finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onFinished: () async => finished = true,
        ),
      ),
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Powerful PDF tools'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your files stay under your control'), findsOneWidget);

    await tester.tap(find.text('Start using ScanLumo'));
    await tester.pump();
    expect(finished, isTrue);
  });
}
