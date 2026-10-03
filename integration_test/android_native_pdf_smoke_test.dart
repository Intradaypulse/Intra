import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfmate/pdf_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native encrypted PDF compress and split smoke test',
      (tester) async {
    final root = await Directory.systemTemp.createTemp('pdfmate_android_it_');
    final docs = await Directory('${root.path}/docs').create();
    final temp = await Directory('${root.path}/temp').create();
    final service = PdfService(
      documentsDirectoryProvider: () async => docs,
      temporaryDirectoryProvider: () async => temp,
    );

    try {
      final source = File('${docs.path}/source.pdf');
      final document = pw.Document();
      for (var i = 1; i <= 4; i++) {
        document.addPage(
          pw.Page(
            build: (_) => pw.Center(child: pw.Text('Android page $i')),
          ),
        );
      }
      await source.writeAsBytes(await document.save(), flush: true);

      expect(await service.pageCount(source), 4);

      final protected = await service.protectPdfAdvanced(
        source,
        ownerPassword: 'owner-secret',
        userPassword: 'open-secret',
      );
      expect(await protected.exists(), isTrue);

      final compressed = await service.compressAdvanced(
        protected,
        CompressionPreset.balanced,
        password: 'open-secret',
      );
      expect(await compressed.file.exists(), isTrue);
      expect(await service.pageCount(compressed.file), 4);
      expect((await service.recoverableOutputs()).map((f) => f.path),
        isNot(contains(compressed.file.path)));
      final savedCompression = await service.publishCompressionPreview(compressed.file);
      expect(await compressed.file.exists(), isFalse);
      expect(await service.pageCount(savedCompression), 4);
      expect((await service.recoverableOutputs()).map((f) => f.path),
        contains(savedCompression.path));

      final parts = await service.splitEveryN(
        protected,
        2,
        password: 'open-secret',
      );
      expect(parts, hasLength(2));
      expect(await service.pageCount(parts[0]), 2);
      expect(await service.pageCount(parts[1]), 2);

      final downloadsResult = await service.savePdfToDownloads(source);
      expect(downloadsResult, isNotEmpty);

      final jpg = File('${temp.path}/storage-smoke.jpg');
      final image = img.Image(width: 24, height: 24);
      await jpg.writeAsBytes(img.encodeJpg(image), flush: true);
      final galleryResult = await service.saveJpgToGallery(jpg);
      expect(galleryResult, isNotEmpty);

      await service.cleanupStaleTemporaryFiles();
      final leftovers = await temp
          .list()
          .where((e) => e.path.contains('pdfmate_secure_tmp_'))
          .toList();
      expect(leftovers, isEmpty);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
