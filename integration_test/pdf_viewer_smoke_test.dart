import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfmate/pdf_service.dart';
import 'package:pdfmate/pdf_viewer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native PDF viewer opens a generated document', (tester) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pdfmate_native_smoke.pdf');

    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (_) => pw.Center(
          child: pw.Text('PDFMate Android integration smoke test'),
        ),
      ),
    );
    await file.writeAsBytes(await document.save(), flush: true);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerScreen(
          path: file.path,
          title: 'Native smoke.pdf',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Native smoke.pdf'), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf_native_viewer')), findsOneWidget);

    if (await file.exists()) {
      await file.delete();
    }
  });

  testWidgets('Android Downloads and Gallery saves return a destination',
      (tester) async {
    final dir = await getTemporaryDirectory();
    final service = PdfService();

    final pdfFile = File('${dir.path}/pdfmate_storage_smoke.pdf');
    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (_) => pw.Center(child: pw.Text('Storage smoke')),
      ),
    );
    await pdfFile.writeAsBytes(await document.save(), flush: true);

    final downloadResult = await service.savePdfToDownloads(pdfFile);
    expect(downloadResult, isNotEmpty);

    final jpgFile = File('${dir.path}/pdfmate_storage_smoke.jpg');
    final image = img.Image(width: 16, height: 16);
    await jpgFile.writeAsBytes(img.encodeJpg(image), flush: true);

    final galleryResult = await service.saveJpgToGallery(jpgFile);
    expect(galleryResult, isNotEmpty);

    if (await pdfFile.exists()) await pdfFile.delete();
    if (await jpgFile.exists()) await jpgFile.delete();
  });

}
