import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdfmate/pdf_service.dart';

void main() {
  late Directory root;
  late Directory docs;
  late Directory temp;
  late PdfService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pdfmate_regression_');
    docs = await Directory('${root.path}/docs').create();
    temp = await Directory('${root.path}/temp').create();
    service = PdfService(
      documentsDirectoryProvider: () async => docs,
      temporaryDirectoryProvider: () async => temp,
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<File> createThreePagePdf() async {
    final doc = pw.Document();
    for (var i = 1; i <= 3; i++) {
      doc.addPage(
        pw.Page(
          build: (_) => pw.Center(child: pw.Text('Regression page $i')),
        ),
      );
    }
    final file = File('${docs.path}/source.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  test('encrypted PDF compression accepts the correct user password', () async {
    final source = await createThreePagePdf();
    final encrypted = await service.protectPdfAdvanced(
      source,
      ownerPassword: 'owner-secret',
      userPassword: 'open-secret',
    );

    final result = await service.compressAdvanced(
      encrypted,
      CompressionPreset.balanced,
      password: 'open-secret',
    );

    expect(await result.file.exists(), isTrue);
    expect(await service.pageCount(result.file), 3);

    final leftovers = await temp
        .list()
        .where((e) => e.path.contains('pdfmate_secure_tmp_'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('encrypted Every-N split decrypts internally and preserves pages',
      () async {
    final source = await createThreePagePdf();
    final encrypted = await service.protectPdfAdvanced(
      source,
      ownerPassword: 'owner-secret',
      userPassword: 'open-secret',
    );

    final outputs = await service.splitEveryN(
      encrypted,
      2,
      password: 'open-secret',
    );

    expect(outputs, hasLength(2));
    expect(await service.pageCount(outputs[0]), 2);
    expect(await service.pageCount(outputs[1]), 1);

    final leftovers = await temp
        .list()
        .where((e) => e.path.contains('pdfmate_secure_tmp_'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('managed decrypted temporary file is securely cleaned', () async {
    final source = await createThreePagePdf();
    final encrypted = await service.protectPdfAdvanced(
      source,
      ownerPassword: 'owner-secret',
      userPassword: 'open-secret',
    );

    final decrypted =
        await service.decryptToTemporary(encrypted, 'open-secret');
    expect(await decrypted.exists(), isTrue);
    expect(service.isManagedTemporaryFile(decrypted), isTrue);

    await service.secureDeleteTemporary(decrypted);
    expect(await decrypted.exists(), isFalse);
  });

  test('pdf engine preserves Unicode watermark text for extraction', () async {
    final source = await createThreePagePdf();
    final output = File('${docs.path}/unicode-overlay.pdf');
    final pdf = Pdf();
    PdfEditor? editor;
    final sink = await FileSink.create(output);
    try {
      editor = await pdf.edit(FileSource(source));
      await editor.addWatermark(
        0,
        'नमस्ते 世界 日本語 한국어',
        style: const PdfWatermarkStyle(
          fontSize: 10,
          opacity: 0.001,
          color: PdfColor.black,
        ),
        position: const PdfWatermarkPosition.exact(
          x: 20,
          y: 20,
          width: 300,
          height: 30,
        ),
        layer: PdfWatermarkLayer.background,
      );
      await editor.save(sink);
      await sink.close();

      final reopened = await pdf.open(FileSource(output));
      try {
        final text = await reopened.extract(pages: const PdfPages.single(0));
        expect(text, contains('नमस्ते'));
        expect(text, contains('世界'));
        expect(text, contains('日本語'));
        expect(text, contains('한국어'));
      } finally {
        await reopened.dispose();
      }
    } finally {
      await editor?.dispose();
      await pdf.dispose();
    }
  });


  test('native PDF editor preserves Unicode OCR text in incremental save',
      () async {
    final source = await createThreePagePdf();
    final engine = Pdf();
    final editor = await engine.edit(FileSource(source));
    final output = File('${docs.path}/unicode_overlay.pdf');
    final sink = await FileSink.create(output);
    try {
      await editor.addWatermark(
        0,
        'नमस्ते 世界 日本語 한국어',
        style: const PdfWatermarkStyle(
          opacity: 0.001,
          fontSize: 12,
          rotation: 0,
        ),
        position: const PdfWatermarkPosition.exact(
          x: 40,
          y: 40,
          width: 300,
          height: 24,
        ),
        layer: PdfWatermarkLayer.background,
      );
      await editor.save(
        sink,
        options: const PdfSaveOptions.incremental(),
      );
      await sink.close();
    } finally {
      await editor.dispose();
      await engine.dispose();
    }

    final reader = Pdf();
    PdfDoc? doc;
    try {
      doc = await reader.open(FileSource(output));
      final text = await doc.extract(pages: const PdfPages.single(0));
      expect(text, contains('नमस्ते'));
      expect(text, contains('世界'));
      expect(text, contains('日本語'));
      expect(text, contains('한국어'));
    } finally {
      await doc?.dispose();
      await reader.dispose();
    }
  });

  test('scanner temporary page files are deleted after PDF assembly', () async {
    final pageDoc = pw.Document();
    pageDoc.addPage(
      pw.Page(build: (_) => pw.Center(child: pw.Text('Scanned page'))),
    );
    final sourcePdf = File('${temp.path}/seed.pdf');
    await sourcePdf.writeAsBytes(await pageDoc.save(), flush: true);

    // Reuse a tiny PNG rendered from the PDF service path contract by writing
    // a 1x1 transparent PNG fixture directly.
    final page = File('${temp.path}/pdfmate_scan_fixture.png');
    await page.writeAsBytes(const <int>[
      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
      0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
      0, 0, 0, 13, 73, 68, 65, 84, 8, 215, 99, 248, 207, 192, 240,
      31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69,
      78, 68, 174, 66, 96, 130,
    ], flush: true);

    final output = await service.createScannedPdfFromFiles([page.path]);
    expect(await output.exists(), isTrue);
    expect(await page.exists(), isFalse);
  });

}