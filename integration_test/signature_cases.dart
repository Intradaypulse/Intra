import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdfmate/pdf_service.dart';
import 'package:pdfmate/signature_screen.dart';
import 'package:pdfmate/signature_store.dart';
import 'package:signature/signature.dart';

void registerSignatureCases() {
  testWidgets('Android drawn signature saves visible transparent ink on a coloured PDF', (tester) async {
    final root = await (await getTemporaryDirectory()).createTemp('signature_ink_');
    final store = SignatureStore(directoryProvider: () async => Directory('${root.path}/signatures'));
    final service = PdfService(documentsDirectoryProvider: () async => root,
      temporaryDirectoryProvider: () async => root);
    Uint8List? exported;
    try {
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: Center(child: TextButton(onPressed: () async {
          exported = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(
            builder: (_) => SignatureScreen(store: store)));
        }, child: const Text('Open signature')))))));
      await tester.tap(find.text('Open signature'));
      await tester.pumpAndSettle();
      final canvas = tester.getRect(find.byType(Signature));
      final start = canvas.center - const Offset(60, 35);
      final gesture = await tester.startGesture(start);
      for (final delta in [const Offset(30, 65), const Offset(55, 10),
        const Offset(80, 60), const Offset(120, 0)]) {
        await gesture.moveTo(start + delta);
        await tester.pump();
      }
      await gesture.up();
      await tester.tap(find.text('Use signature'));
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (exported == null && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(exported, isNotNull);
      final ink = img.decodePng(exported!)!;
      expect(ink.width, inInclusiveRange(120, 135));
      expect(ink.height, inInclusiveRange(65, 80));
      expect(ink.getPixel(0, 0).a, 0);
      expect(await (await store.load()).single.file.readAsBytes(), exported);

      final pdf = pw.Document()..addPage(pw.Page(
        pageFormat: const pf.PdfPageFormat(400, 600), margin: pw.EdgeInsets.zero,
        build: (_) => pw.Container(width: 400, height: 600, color: pf.PdfColors.red)));
      final source = await File('${root.path}/red.pdf').writeAsBytes(await pdf.save());
      final before = img.decodeImage((await service.renderPage(source, 0, width: 800))!)!;
      expect(before.getPixel(20, 20).r, greaterThan(240));
      expect(before.getPixel(20, 20).g, lessThan(100));
      for (final angle in [0, 35]) {
        final rotated = img.copyRotate(ink, angle: angle, interpolation: img.Interpolation.linear);
        const width = 120.0;
        final height = width * rotated.height / rotated.width;
        final signed = await service.stampSignatureAt(source, Uint8List.fromList(img.encodePng(rotated)),
          page: 0, rect: PdfRect(x: 40, y: 60, width: width, height: height));
        final after = img.decodeImage((await service.renderPage(signed, 0, width: 800))!)!;
        final dark = after.where((p) => p.r < 80 && p.g < 80 && p.b < 80)
          .map((p) => (p.x, p.y)).toList();
        expect(dark.length, greaterThan(300), reason: 'Visible black ink at angle $angle');
        // Check the actual persisted PDF, not just the Flutter preview.
        final top = (600 - 60 - height) * 2;
        expect(dark.every((p) => p.$1 >= 78 && p.$1 <= 322 &&
          p.$2 >= top - 2 && p.$2 <= 1082), isTrue);
        var changed = 0;
        var white = 0;
        for (final pixel in after) {
          final old = before.getPixel(pixel.x, pixel.y);
          if (pixel.r != old.r || pixel.g != old.g || pixel.b != old.b) changed++;
          if (pixel.r > 240 && pixel.g > 240 && pixel.b > 240) white++;
        }
        expect(changed, greaterThan(300));
        expect(changed, lessThan(width * height * 4 * .35));
        expect(white, 0, reason: 'Transparent signature must not cover the document with white');
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
