import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:printing/printing.dart';

void main() {
  Future<void> verifyEmbeddedUnicode({
    required String text,
    required Future<pw.Font> Function() loadFont,
    required String fileName,
  }) async {
    final root = await Directory.systemTemp.createTemp('pdfmate_unicode_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final font = await loadFont();
    final output = File('${root.path}/$fileName.pdf');

    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (_) => pw.Center(
          child: pw.Text(
            text,
            style: pw.TextStyle(font: font, fontSize: 18),
          ),
        ),
      ),
    );
    await output.writeAsBytes(await document.save(), flush: true);

    final pdf = Pdf();
    PdfDoc? doc;
    try {
      doc = await pdf.open(FileSource(output));
      final extracted = await doc.extract(pages: const PdfPages.all());
      expect(extracted, contains(text));
    } finally {
      await doc?.dispose();
      await pdf.dispose();
    }
  }

  test('Devanagari fallback font embeds searchable Unicode text', () async {
    await verifyEmbeddedUnicode(
      text: 'नमस्ते',
      loadFont: PdfGoogleFonts.notoSansDevanagariRegular,
      fileName: 'devanagari',
    );
  });

  test('CJK fallback font embeds searchable Unicode text', () async {
    await verifyEmbeddedUnicode(
      text: '世界',
      loadFont: PdfGoogleFonts.notoSansSCRegular,
      fileName: 'cjk',
    );
  });
}
