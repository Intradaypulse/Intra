import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
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
}
