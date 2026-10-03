import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:pdfmate/pdf_service.dart';
import 'overlay_fixture.dart';

void registerDeepAuditCases() {
  for (final userPassword in ['', 'open-secret']) {
    testWidgets('native OCR requires owner authentication userPassword=$userPassword', (tester) async {
      final root = await (await getTemporaryDirectory()).createTemp('owner_ocr_');
      final service = PdfService(documentsDirectoryProvider: () async => root,
        temporaryDirectoryProvider: () async => root);
      final engine = Pdf();
      PdfDoc? result;
      try {
        final raw = File('${root.path}/raw.pdf');
        final pdf = pw.Document()..addPage(pw.Page(build: (_) => pw.SizedBox()));
        await raw.writeAsBytes(await pdf.save());
        final protected = await service.protectPdfAdvanced(raw,
          ownerPassword: 'owner-secret', userPassword: userPassword, readOnly: true);
        await expectLater(service.checkOcrPermission(protected, password: userPassword),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'OCR_OWNER_PASSWORD_REQUIRED')));
        await expectLater(service.checkOcrPermission(protected, password: 'wrong'),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'OCR_WRONG_PASSWORD')));
        await service.checkOcrPermission(protected, password: 'owner-secret');
        final manifest = await File('${root.path}/words.jsonl').writeAsString(jsonEncode({
          'page': 0, 'words': [{'text': 'Authorized', 'x': 30, 'y': 80,
            'width': 100, 'height': 20, 'angle': 0}],
        }));
        final output = File('${root.path}/output.pdf');
        await const MethodChannel('pdfmate/unicode_overlay').invokeMethod<void>('append', {
          'source': protected.path, 'output': output.path, 'manifest': manifest.path,
          'password': 'owner-secret',
        });
        result = await engine.open(FileSource(output), password: 'owner-secret');
        expect(await result.extract(pages: PdfPages.single(0)), contains('Authorized'));
      } finally {
        await result?.dispose(); await engine.dispose(); await root.delete(recursive: true);
      }
    });
  }
  testWidgets('invisible Latin Hindi CJK and supplementary Unicode preserve cropped rotated pixels', (tester) async {
    final root = await (await getTemporaryDirectory()).createTemp('ocr_geometry_');
    final engine = Pdf();
    PdfDoc? before, after;
    PdfEditor? editor;
    try {
      final raw = File('${root.path}/raw.pdf');
      final pdf = pw.Document();
      for (var i = 0; i < 4; i++) {
        pdf.addPage(pw.Page(pageFormat: const pf.PdfPageFormat(600, 800),
          build: (_) => pw.SizedBox())); // No opaque image to hide painted text.
      }
      await raw.writeAsBytes(await pdf.save());
      editor = await engine.edit(FileSource(raw));
      for (var i = 0; i < 4; i++) {
        await editor.setPageCropBox(i, const PdfRect(x: 100, y: 200, width: 300, height: 400));
        await editor.setPageRotation(i, degrees: i * 90);
      }
      final source = File('${root.path}/source.pdf');
      final sink = await FileSink.create(source);
      try { await editor.save(sink); } finally { await sink.close(); }
      await editor.dispose(); editor = null;
      final manifest = await File('${root.path}/words.jsonl').writeAsString([
        for (var i = 0; i < 4; i++) jsonEncode({'page': i, 'words': [
          {'text': 'Invoice नमस्ते 中文 日本語 한국어 𠀀 😀', 'x': 30, 'y': 80,
           'width': 180, 'height': 20, 'angle': 0},
        ]}),
      ].join('\n'));
      final output = File('${root.path}/output.pdf');
      await const MethodChannel('pdfmate/unicode_overlay').invokeMethod<void>('append', {
        'source': source.path, 'output': output.path, 'manifest': manifest.path,
      });
      before = await engine.open(FileSource(source));
      after = await engine.open(FileSource(output));
      final service = PdfService();
      for (var i = 0; i < 4; i++) {
        final text = (await after.extract(pages: PdfPages.single(i))).replaceAll(RegExp(r'\s+'), '');
        expect(text, contains('Invoiceनमस्ते中文日本語한국어𠀀😀'));
        expect(await service.renderPage(output, i), await service.renderPage(source, i));
        final hit = (await after.search(query: 'Invoice', pages: PdfPages.single(i))).single;
        // Search exposes displayed MediaBox coordinates after the PDF page rotation.
        final expected = [(130.0, 520.0), (230.0, 420.0), (230.0, 520.0), (230.0, 320.0)][i];
        // Search returns the whole text span, not the substring's box. At
        // rotation changes the returned coordinate frame; check that the
        // known displayed baseline anchor lies in the span instead.
        expect(hit.rect.x, lessThanOrEqualTo(expected.$1 + 2));
        expect(hit.rect.right, greaterThanOrEqualTo(expected.$1 - 2));
        expect(hit.rect.y, lessThanOrEqualTo(expected.$2 + 2));
        expect(hit.rect.bottom, greaterThanOrEqualTo(expected.$2 - 2));
        expect(hit.rect.width * hit.rect.height, lessThan(180 * 30));
      }
    } finally {
      await editor?.dispose(); await before?.dispose(); await after?.dispose();
      await engine.dispose(); await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('cropped Hindi OCR scales image coordinates to the visible box and deduplicates', (tester) async {
    final root = await (await getTemporaryDirectory()).createTemp('crop_ocr_e2e_');
    final docs = await Directory('${root.path}/docs').create();
    final temp = await Directory('${root.path}/temp').create();
    final service = PdfService(documentsDirectoryProvider: () async => docs,
      temporaryDirectoryProvider: () async => temp);
    final engine = Pdf();
    PdfEditor? editor;
    PdfDoc? result;
    try {
      final pdf = pw.Document();
      pdf.addPage(pw.Page(pageFormat: const pf.PdfPageFormat(600, 800), margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(children: [pw.Positioned(left: 150, top: 200,
          child: pw.SizedBox(width: 300, height: 150,
            child: pw.Image(pw.MemoryImage(base64Decode(hindiScanBase64)))))])));
      final turned = img.copyRotate(img.decodeImage(base64Decode(hindiScanBase64))!, angle: -90);
      pdf.addPage(pw.Page(pageFormat: const pf.PdfPageFormat(600, 800), margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(children: [pw.Positioned(left: 225, top: 150,
          child: pw.SizedBox(width: 150, height: 300,
            child: pw.Image(pw.MemoryImage(img.encodePng(turned)))))])));
      final raw = await File('${docs.path}/raw.pdf').writeAsBytes(await pdf.save());
      editor = await engine.edit(FileSource(raw));
      for (var page = 0; page < 2; page++) {
        await editor.setPageCropBox(page, const PdfRect(x: 100, y: 350, width: 400, height: 300));
        await editor.setPageRotation(page, degrees: page * 90);
      }
      final source = File('${docs.path}/crop.pdf');
      final sink = await FileSink.create(source);
      try { await editor.save(sink); } finally { await sink.close(); }
      await editor.dispose(); editor = null;
      final output = await service.makeSearchablePdf(source, script: TextRecognitionScript.devanagiri);
      result = await engine.open(FileSource(output));
      final hits = await result.search(query: 'नमस्ते', pages: PdfPages.single(0));
      expect(hits, hasLength(1));
      expect(hits.single.rect.x, closeTo(175, 15));
      expect(hits.single.rect.y, inInclusiveRange(500, 580));
      for (var page = 0; page < 2; page++) {
        expect(await service.renderPage(output, page), await service.renderPage(source, page));
        expect('नमस्ते'.allMatches(await result.extract(pages: PdfPages.single(page))).length, 1);
      }
      final second = await service.makeSearchablePdf(output, script: TextRecognitionScript.devanagiri);
      await result.dispose(); result = await engine.open(FileSource(second));
      for (var page = 0; page < 2; page++) {
        expect('नमस्ते'.allMatches(await result.extract(pages: PdfPages.single(page))).length, 1);
      }
    } finally {
      await editor?.dispose(); await result?.dispose(); await engine.dispose();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
