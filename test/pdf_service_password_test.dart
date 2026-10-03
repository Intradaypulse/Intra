import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:pdfmate/pdf_service.dart';
import 'package:pdfmate/signature_geometry.dart';
import 'package:pdf/pdf.dart' as format;

final class _PickedFile extends PlatformFile {
  _PickedFile(this.path);
  @override
  final String path;
  @override
  String get name => File(path).uri.pathSegments.last;
  @override
  Future<Uint8List> readAsBytes() => File(path).readAsBytes();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CloudFile extends PlatformFile {
  @override
  String? get path => null;
  @override
  String get name => 'cloud.pdf';
  @override
  Future<Uint8List> readAsBytes() => throw StateError('Whole-file reads forbidden');
  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield Uint8List.fromList([1, 2]);
    yield Uint8List.fromList([3, 4]);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PickerService extends PdfService {
  _PickerService(Directory docs, Directory temp, this.files)
      : super(documentsDirectoryProvider: () async => docs,
              temporaryDirectoryProvider: () async => temp);
  final List<PlatformFile> files;
  @override
  Future<List<PlatformFile>> pickPdfs() async => files;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
        pw.Page(build: (_) => pw.Center(child: pw.Text('Regression page $i'))),
      );
    }
    final file = File('${docs.path}/source.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  test('pathless cloud picker streams without whole-file allocation', () async {
    final picker = _PickerService(docs, temp, [_CloudFile()]);
    final files = await picker.pickPdfFiles();
    expect(await files.single.readAsBytes(), [1, 2, 3, 4]);
    await picker.secureDeleteTemporary(files.single);
  });

  test('failed compression removes its incomplete output', () async {
    final invalid = await File('${docs.path}/invalid.pdf').writeAsString('invalid');
    final before = (await docs.list().toList()).map((e) => e.path).toSet();
    await expectLater(service.compressAdvanced(invalid, CompressionPreset.balanced), throwsA(anything));
    expect((await docs.list().toList()).map((e) => e.path).toSet(), before);
  });

  test('managed picker copies retain original display names', () async {
    final source = await createThreePagePdf();
    final picker = _PickerService(docs, temp, [_PickedFile(source.path)]);
    final files = await picker.pickPdfFiles();
    expect(files.single.path, isNot(source.path));
    expect(picker.displayName(files.single), 'source.pdf');
    await picker.secureDeleteTemporary(files.single);
    expect(await source.exists(), isTrue);
  });

  test(
    'organizer removes work and partial output when extraction fails',
    () async {
      final source = await createThreePagePdf();
      final before = (await docs.list().toList()).map((e) => e.path).toSet();
      await expectLater(
        service.organizePdf(source, pageOrder: [999], rotations: {}),
        throwsA(anything),
      );
      expect((await docs.list().toList()).map((e) => e.path).toSet(), before);
      expect(await temp.list().toList(), isEmpty);
    },
  );

  test('custom split removes earlier parts after a later invalid range', () async {
    final source = await createThreePagePdf();
    final original = (await docs.list().toList()).map((e) => e.path).toSet();
    await expectLater(
      service.splitRanges(source, [[0], [999]]),
      throwsA(anything),
    );
    expect((await docs.list().toList()).map((e) => e.path).toSet(), original);
  });

  test('failed protect and unlock remove partial outputs', () async {
    final invalid = await File('${docs.path}/invalid.pdf').writeAsString('not a PDF');
    final before = (await docs.list().toList()).map((e) => e.path).toSet();
    await expectLater(service.protectPdfAdvanced(invalid, ownerPassword: 'secret'),
      throwsA(anything));
    expect((await docs.list().toList()).map((e) => e.path).toSet(), before);
    await expectLater(service.unlockPdf(invalid, 'wrong'), throwsA(anything));
    expect((await docs.list().toList()).map((e) => e.path).toSet(), before);
  });

  test('failed merge and signature remove partial outputs', () async {
    final valid = await createThreePagePdf();
    final invalid = await File('${docs.path}/invalid.pdf').writeAsString('invalid');
    final before = (await docs.list().toList()).map((e) => e.path).toSet();
    await expectLater(service.mergeFiles([valid, invalid]), throwsA(anything));
    expect((await docs.list().toList()).map((e) => e.path).toSet(), before);
    await expectLater(service.stampSignatureAt(invalid, Uint8List.fromList([1, 2]),
      page: 0, rect: PdfRect(x: 0, y: 0, width: 10, height: 10)), throwsA(anything));
    expect((await docs.list().toList()).map((e) => e.path).toSet(), before);
  });

  test('batch picker rolls back earlier copies when a later source is missing', () async {
    final valid = await createThreePagePdf();
    final picker = _PickerService(docs, temp, [
      _PickedFile(valid.path),
      _PickedFile('${docs.path}/missing.pdf'),
    ]);
    await expectLater(picker.pickPdfFiles(), throwsA(anything));
    expect(await temp.list().toList(), isEmpty);
    expect(await valid.exists(), isTrue);
  });

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

  test(
    'encrypted Every-N split decrypts internally and preserves pages',
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
    },
  );

  test(
    'startup cleanup preserves a temporary document owned by another active service',
    () async {
      final source = await createThreePagePdf();
      final protected = await service.protectPdfAdvanced(
        source,
        ownerPassword: 'owner',
        userPassword: 'reader',
      );
      final readable = await service.decryptToTemporary(protected, 'reader');
      final other = PdfService(
        documentsDirectoryProvider: () async => docs,
        temporaryDirectoryProvider: () async => temp,
      );
      await other.cleanupStaleTemporaryFiles();
      expect(await readable.exists(), isTrue);
      await service.secureDeleteTemporary(readable);
    },
  );

  test(
    'a user document with the temporary prefix is never deleted by name alone',
    () async {
      final original = await File(
        '${docs.path}/pdfmate_secure_tmp_my_original.pdf',
      ).writeAsString('original');
      await service.secureDeleteTemporary(original);
      expect(await original.readAsString(), 'original');
    },
  );

  test('managed decrypted temporary file is securely cleaned', () async {
    final source = await createThreePagePdf();
    final encrypted = await service.protectPdfAdvanced(
      source,
      ownerPassword: 'owner-secret',
      userPassword: 'open-secret',
    );

    final decrypted = await service.decryptToTemporary(
      encrypted,
      'open-secret',
    );
    expect(await decrypted.exists(), isTrue);
    expect(service.isManagedTemporaryFile(decrypted), isTrue);

    await service.secureDeleteTemporary(decrypted);
    expect(await decrypted.exists(), isFalse);
  });

  test(
    'native PDF editor preserves Latin OCR text in incremental save',
    () async {
      final source = await createThreePagePdf();
      final engine = Pdf();
      final editor = await engine.edit(FileSource(source));
      final output = File('${docs.path}/latin_overlay.pdf');
      final sink = await FileSink.create(output);
      try {
        await editor.addWatermark(
          0,
          'OCR_OVERLAY_TOKEN',
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
        await editor.save(sink, options: const PdfSaveOptions.incremental());
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
        expect(text, contains('OCR_OVERLAY_TOKEN'));
        expect(text, contains('Regression page 1'));
      } finally {
        await doc?.dispose();
        await reader.dispose();
      }
    },
  );

  for (final script in <String, String>{
    'Chinese': '世界',
    'Japanese': 'こんにちは',
    'Korean': '안녕하세요',
  }.entries) {
    test('native OCR overlay extracts ${script.key} text', () async {
      final source = await createThreePagePdf();
      final engine = Pdf();
      final editor = await engine.edit(FileSource(source));
      final output = File('${docs.path}/overlay_${script.key}.pdf');
      final sink = await FileSink.create(output);
      try {
        await editor.addWatermark(
          0,
          script.value,
          style: const PdfWatermarkStyle(opacity: 0.001, fontSize: 12),
          position: const PdfWatermarkPosition.exact(
            x: 40,
            y: 40,
            width: 300,
            height: 24,
          ),
          layer: PdfWatermarkLayer.background,
        );
        await editor.save(sink, options: const PdfSaveOptions.incremental());
        await sink.close();
      } finally {
        await editor.dispose();
        await engine.dispose();
      }

      final reader = Pdf();
      PdfDoc? doc;
      try {
        doc = await reader.open(FileSource(output));
        final extracted = await doc.extract(pages: const PdfPages.single(0));
        expect(extracted, contains(script.value));
        expect(extracted, contains('Regression page 1'));
      } finally {
        await doc?.dispose();
        await reader.dispose();
      }
    });
  }

  test('bundled Hindi OCR font produces extractable PDF text', () async {
    final fontBytes = await rootBundle.load(
      'assets/fonts/NotoSansDevanagariOCR.ttf',
    );
    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (_) => pw.Text(
          'नमस्ते',
          style: pw.TextStyle(font: pw.Font.ttf(fontBytes)),
        ),
      ),
    );
    final output = File('${docs.path}/embedded_hindi.pdf');
    await output.writeAsBytes(await document.save());
    final reader = Pdf();
    PdfDoc? doc;
    try {
      doc = await reader.open(FileSource(output));
      expect(
        await doc.extract(pages: const PdfPages.single(0)),
        contains('नमस्ते'),
      );
    } finally {
      await doc?.dispose();
      await reader.dispose();
    }
  });

  for (final rotation in [0, 90, 180, 270]) {
    test('signature render matches cropped preview at rotation $rotation', () async {
      final document = pw.Document()..addPage(pw.Page(
        pageFormat: const format.PdfPageFormat(400, 600), build: (_) => pw.SizedBox()));
      final source = await File('${docs.path}/blank.pdf').writeAsBytes(await document.save());
      final engine = Pdf();
      final editor = await engine.edit(FileSource(source));
      final cropped = File('${docs.path}/crop_$rotation.pdf');
      final sink = await FileSink.create(cropped);
      try {
        await editor.setPageCropBox(0, const PdfRect(x: 20, y: 30, width: 200, height: 300));
        await editor.setPageRotation(0, degrees: rotation);
        await editor.save(sink);
      } finally { await sink.close(); await editor.dispose(); await engine.dispose(); }
      final box = await service.pageVisibleBox(cropped, 0);
      final rect = signaturePdfRect(const Rect.fromLTWH(10, 20, 80, 30), box.width, box.height, rotation);
      final signature = img.Image(width: 80, height: 30, numChannels: 4);
      img.fill(signature, color: img.ColorRgba8(255, 0, 0, 255));
      final png = img.encodePng(img.copyRotate(signature, angle: -rotation));
      final signed = await service.stampSignatureAt(cropped, png, page: 0,
        rect: PdfRect(x: rect.left + box.x, y: rect.top + box.y, width: rect.width, height: rect.height));
      final rendered = img.decodeImage((await service.renderPage(signed, 0, width: 600))!)!;
      final red = [for (final pixel in rendered)
        if (pixel.r > 200 && pixel.g < 60 && pixel.b < 60) (pixel.x, pixel.y)];
      expect(red, isNotEmpty);
      final xs = red.map((p) => p.$1).toList()..sort();
      final ys = red.map((p) => p.$2).toList()..sort();
      final scale = rendered.width / (rotation % 180 == 0 ? box.width : box.height);
      expect(xs.first, closeTo(10 * scale, 3));
      expect(ys.first, closeTo(20 * scale, 3));
      expect(xs.last + 1, closeTo(90 * scale, 3));
      expect(ys.last + 1, closeTo(50 * scale, 3));
    });
  }

  test('failed scan encoding retains captures for retry', () async {
    final page = await File('${temp.path}/pdfmate_scan_broken.jpg').writeAsString('invalid image');
    await expectLater(service.createScannedPdfFromFiles([page.path]), throwsA(anything));
    expect(await page.readAsString(), 'invalid image');
    expect(await service.recoverableOutputs(), isEmpty);
  });

  test('owner-only encryption is remembered for explicit output consent', () async {
    final original = await createThreePagePdf();
    final encrypted = await service.protectPdfAdvanced(original, ownerPassword: 'owner-only');
    await service.pageCount(encrypted);
    expect(service.wasProtected(encrypted), isTrue);
  });

  test('visible page geometry intersects crop and media boxes', () async {
    final source = await createThreePagePdf();
    final engine = Pdf();
    final editor = await engine.edit(FileSource(source));
    final changed = File('${docs.path}/cropped.pdf');
    final sink = await FileSink.create(changed);
    try {
      await editor.setPageMediaBox(0, const PdfRect(x: 20, y: 30, width: 600, height: 800));
      await editor.setPageCropBox(0, const PdfRect(x: 50, y: 70, width: 400, height: 500));
      await editor.save(sink);
    } finally { await sink.close(); await editor.dispose(); await engine.dispose(); }
    final box = await service.pageVisibleBox(changed, 0);
    expect([box.x, box.y, box.width, box.height], [50, 70, 400, 500]);
  });

  test('reserved scan destination publishes atomically and cannot overwrite completion', () async {
    final page = File('${temp.path}/reserved.png');
    await page.writeAsBytes(img.encodePng(img.Image(width: 24, height: 48)));
    final destination = File('${docs.path}/Scan_session.pdf');
    final output = await service.createScannedPdfFromFiles([page.path], destination: destination);
    expect(output.path, destination.path);
    expect(await service.pageCount(output), 1);
    expect(await File('${destination.path}.pending').exists(), isFalse);
    final bytes = await output.readAsBytes();
    await expectLater(service.createScannedPdfFromFiles([page.path], destination: destination), throwsStateError);
    expect(await output.readAsBytes(), bytes);
    expect(await temp.list().where((f) => f.path != page.path).toList(), isEmpty);
  });

  test('scanner page files are retained until library registration', () async {
    final page = File('${temp.path}/pdfmate_scan_fixture.png');
    await page.writeAsBytes(img.encodePng(img.Image(width: 24, height: 48)));
    final output = await service.createScannedPdfFromFiles([page.path]);
    expect(await output.exists(), isTrue);
    expect(await page.exists(), isTrue);
  });

  test(
    'startup cleanup removes stale scanner pages but keeps fresh ones',
    () async {
      final stale = File('${temp.path}/pdfmate_scan_stale.jpg');
      final fresh = File('${temp.path}/pdfmate_scan_fresh.jpg');
      final unrelated = File('${temp.path}/unrelated.jpg');
      for (final file in [stale, fresh, unrelated]) {
        await file.writeAsBytes(List<int>.filled(128, 42));
      }
      await stale.setLastModified(
        DateTime.now().subtract(const Duration(hours: 2)),
      );

      await service.cleanupStaleTemporaryFiles();

      expect(await stale.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
    },
  );
}
