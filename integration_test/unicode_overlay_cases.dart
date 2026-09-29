import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'overlay_fixture.dart';

void registerUnicodeOverlayCases() {
  testWidgets(
    'Hindi incremental overlay retains source bytes, forms, bookmarks and pixels',
    (tester) async {
      final directory = await Directory(
        (await getTemporaryDirectory()).path,
      ).createTemp('overlay_test_');
      final original = base64Decode(overlayFixtureBase64);
      final source = await File(
        '${directory.path}/source.pdf',
      ).writeAsBytes(original);
      final output = File('${directory.path}/output.pdf');
      final manifest = File('${directory.path}/geometry.jsonl');
      final engine = Pdf();
      PdfDoc? before, after;
      try {
        await manifest.writeAsString(
          [
            for (var page = 0; page < 4; page++)
              jsonEncode({
                'page': page,
                'words': [
                  {
                    'text': 'नमस्ते',
                    'x': 50,
                    'y': 100,
                    'width': 75,
                    'height': 20,
                    'angle': 0,
                  },
                  {
                    'text': 'हिन्दी',
                    'x': 170,
                    'y': 200,
                    'width': 65,
                    'height': 18,
                    'angle': 25,
                  },
                ],
              }),
          ].join('\n'),
        );
        await const MethodChannel('pdfmate/unicode_overlay').invokeMethod<void>(
          'append',
          {
            'source': source.path,
            'output': output.path,
            'manifest': manifest.path,
          },
        );
        final bytes = await output.readAsBytes();
        expect(bytes.length, greaterThan(original.length));
        expect(
          bytes.sublist(0, original.length),
          original,
          reason: 'Incremental output must retain the exact original revision',
        );
        expect(await source.readAsBytes(), original);
        before = await engine.open(FileSource(source));
        after = await engine.open(FileSource(output));
        expect(after.pageCount, 4);
        expect(
          (await after.formFields).map((f) => f.name),
          (await before.formFields).map((f) => f.name),
        );
        expect(
          ((await after.formField('customer'))!.value as PdfTextValue).text,
          ((await before.formField('customer'))!.value as PdfTextValue).text,
        );
        expect(
          (await after.planSplitByBookmarks()).length,
          (await before.planSplitByBookmarks()).length,
        );
        for (var i = 0; i < 4; i++) {
          final text = await after.extract(pages: PdfPages.single(i));
          expect(text.replaceAll(RegExp(r'\s+'), ''), contains('नमस्ते'));
          expect(text.replaceAll(RegExp(r'\s+'), ''), contains('हिन्दी'));
          final a = await before
              .render(
                pages: PdfPages.single(i),
                size: const PdfRenderSize(maxWidth: 600, maxHeight: 800),
              )
              .first;
          final b = await after
              .render(
                pages: PdfPages.single(i),
                size: const PdfRenderSize(maxWidth: 600, maxHeight: 800),
              )
              .first;
          expect(
            b.data,
            a.data,
            reason: 'Invisible overlay must not alter original page $i pixels',
          );
        }
      } finally {
        await before?.dispose();
        await after?.dispose();
        await engine.dispose();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'invalid overlay removes partial output and leaves source intact',
    (tester) async {
      final directory = await Directory(
        (await getTemporaryDirectory()).path,
      ).createTemp('overlay_test_');
      final original = base64Decode(overlayFixtureBase64);
      final source = await File(
        '${directory.path}/source.pdf',
      ).writeAsBytes(original);
      final output = File('${directory.path}/output.pdf');
      final manifest = await File(
        '${directory.path}/bad.jsonl',
      ).writeAsString(jsonEncode({'page': 999, 'words': []}));
      try {
        await expectLater(
          const MethodChannel('pdfmate/unicode_overlay').invokeMethod<void>(
            'append',
            {
              'source': source.path,
              'output': output.path,
              'manifest': manifest.path,
            },
          ),
          throwsA(isA<PlatformException>()),
        );
        expect(await output.exists(), isFalse);
        expect(await source.readAsBytes(), original);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
