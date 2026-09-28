import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

void main() {
  test('incremental Unicode OCR overlay stays searchable', () async {
    final root = await Directory.systemTemp.createTemp('pdfmate_unicode_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final base = File('${root.path}/base.pdf');
    final output = File('${root.path}/searchable.pdf');

    final baseDoc = pw.Document();
    baseDoc.addPage(
      pw.Page(
        build: (_) => pw.Center(child: pw.Text('Base page')),
      ),
    );
    await base.writeAsBytes(await baseDoc.save(), flush: true);

    final pdf = Pdf();
    PdfEditor? editor;
    try {
      editor = await pdf.edit(FileSource(base));
      await editor.addWatermark(
        0,
        'नमस्ते 世界',
        style: const PdfWatermarkStyle(
          fontSize: 12,
          opacity: 0.001,
          rotation: 0,
        ),
        position: const PdfWatermarkPosition.exact(
          x: 40,
          y: 40,
          width: 220,
          height: 24,
        ),
        layer: PdfWatermarkLayer.background,
      );

      final sink = await FileSink.create(output);
      await editor.save(
        sink,
        options: const PdfSaveOptions.incremental(),
      );
      await sink.close();

      final searchable = await pdf.open(FileSource(output));
      try {
        final extracted = await searchable.extract(
          pages: const PdfPages.all(),
        );
        expect(extracted, contains('नमस्ते'));
        expect(extracted, contains('世界'));
      } finally {
        await searchable.dispose();
      }
    } finally {
      await editor?.dispose();
      await pdf.dispose();
    }
  });
}
