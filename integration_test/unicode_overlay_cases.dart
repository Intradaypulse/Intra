import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';
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
                    'text': 'नमस्ते₹—é',
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
          expect(text.replaceAll(RegExp(r'\s+'), ''), contains('नमस्ते₹—é'));
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
    'encrypted Hindi overlay retains encryption and original revision',
    (tester) async {
      final directory = await Directory(
        (await getTemporaryDirectory()).path,
      ).createTemp('overlay_test_');
      final original = base64Decode(encryptedOverlayFixtureBase64);
      final source = await File(
        '${directory.path}/source.pdf',
      ).writeAsBytes(original);
      final output = File('${directory.path}/output.pdf');
      final manifest = await File('${directory.path}/geometry.jsonl')
          .writeAsString(
            jsonEncode({
              'page': 0,
              'words': [
                {
                  'text': 'नमस्ते',
                  'x': 50,
                  'y': 100,
                  'width': 75,
                  'height': 20,
                  'angle': 0,
                },
              ],
            }),
          );
      final engine = Pdf();
      PdfDoc? document;
      try {
        await const MethodChannel(
          'pdfmate/unicode_overlay',
        ).invokeMethod<void>('append', {
          'source': source.path,
          'output': output.path,
          'manifest': manifest.path,
          'password': 'owner-secret',
        });
        expect(
          (await output.readAsBytes()).sublist(0, original.length),
          original,
        );
        document = await engine.open(
          FileSource(output),
          password: 'open-secret',
        );
        expect(document.isEncrypted, isTrue);
        expect(
          (await document.extract(
            pages: PdfPages.single(0),
          )).replaceAll(RegExp(r'\s+'), ''),
          contains('नमस्ते'),
        );
      } finally {
        await document?.dispose();
        await engine.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    '300-page Unicode overlay shares font and cleans native scratch',
    (tester) async {
      final temp = await getTemporaryDirectory();
      final directory = await Directory(temp.path).createTemp('overlay_test_');
      final source = File('${directory.path}/source.pdf');
      final output = File('${directory.path}/output.pdf');
      final manifest = File('${directory.path}/geometry.jsonl');
      final pdf = pw.Document();
      for (var i = 0; i < 300; i++) {
        pdf.addPage(pw.Page(build: (_) => pw.SizedBox()));
      }
      await source.writeAsBytes(await pdf.save());
      final writer = manifest.openWrite();
      for (var i = 0; i < 300; i++) {
        writer.writeln(
          jsonEncode({
            'page': i,
            'words': [
              {
                'text': 'हिन्दी',
                'x': 50,
                'y': 100,
                'width': 75,
                'height': 20,
                'angle': 0,
              },
            ],
          }),
        );
      }
      await writer.close();
      final engine = Pdf();
      PdfDoc? document;
      try {
        await const MethodChannel('pdfmate/unicode_overlay').invokeMethod<void>(
          'append',
          {
            'source': source.path,
            'output': output.path,
            'manifest': manifest.path,
          },
        );
        document = await engine.open(FileSource(output));
        expect(document.pageCount, 300);
        expect(
          (await document.extract(
            pages: PdfPages.single(299),
          )).replaceAll(RegExp(r'\s+'), ''),
          contains('हिन्दी'),
        );
        expect(
          await output.length(),
          lessThan(await source.length() + 4 * 1024 * 1024),
        );
        expect(
          await temp
              .list()
              .where(
                (f) => f.path.split('/').last.startsWith('pdfmate_overlay_'),
              )
              .toList(),
          isEmpty,
        );
      } finally {
        await document?.dispose();
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
