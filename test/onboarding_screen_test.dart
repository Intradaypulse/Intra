import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/onboarding_screen.dart';

void main() {
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

    await tester.tap(find.text('Start using PDFMate'));
    await tester.pump();
    expect(finished, isTrue);
  });
}
