import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

void main() {
  test('invisible OCR watermark preserves Unicode text for extraction',
      () async {
    final root = await Directory.systemTemp.createTemp('pdfmate_unicode_');
    final source = File('${root.path}/source.pdf');
    final output = File('${root.path}/searchable.pdf');

    try {
      final base = pw.Document();
      base.addPage(
        pw.Page(
          build: (_) => pw.Center(child: pw.Text('Base page')),
        ),
      );
      await source.writeAsBytes(await base.save(), flush: true);

      final engine = Pdf();
      final editor = await engine.edit(FileSource(source));
      final sink = await FileSink.create(output);
      const unicode = 'नमस्ते 世界 こんにちは 한국어';

      await editor.addWatermark(
        0,
        unicode,
        style: const PdfWatermarkStyle(
          opacity: 0,
          fontSize: 12,
          rotation: 0,
        ),
        position: const PdfWatermarkPosition.exact(
          x: 30,
          y: 30,
          width: 400,
          height: 30,
        ),
        layer: PdfWatermarkLayer.background,
      );
      await editor.save(
        sink,
        options: const PdfSaveOptions.incremental(),
      );
      await sink.close();
      await editor.dispose();

      final doc = await engine.open(FileSource(output));
      final extracted = await doc.extract(pages: const PdfPages.all());
      await doc.dispose();
      await engine.dispose();

      expect(extracted, contains('नमस्ते'));
      expect(extracted, contains('世界'));
      expect(extracted, contains('こんにちは'));
      expect(extracted, contains('한국어'));
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
