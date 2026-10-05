import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/downloads_screen.dart';

void main() {
  testWidgets(
    'downloads refreshes current exports and opens the selected version',
    (tester) async {
      const channel = MethodChannel('pdfmate/downloads');
      var version = 1;
      String? opened;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'list')
          return [
            {
              'uri': 'content://media/external/file/$version',
              'name': 'signed-v$version.pdf',
              'modified': 1000,
            },
          ];
        if (call.method == 'open')
          opened = (call.arguments as Map)['uri'] as String;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: DownloadsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('signed-v1.pdf'), findsOneWidget);
      version = 2;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('signed-v1.pdf'), findsNothing);
      await tester.tap(find.text('signed-v2.pdf'));
      await tester.pumpAndSettle();
      expect(opened, 'content://media/external/file/2');
    },
  );
}
