import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/manual_crop_screen.dart';

void main() {
  testWidgets('missing crop photo shows retry instead of an endless spinner', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ManualCropScreen(imagePath: '/nonexistent/pdfmate_crop.jpg'),
        ),
      );
      // Let the real file I/O error complete outside the fake test clock.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.textContaining('Could not prepare photo:'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
