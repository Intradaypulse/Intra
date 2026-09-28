import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfmate/main.dart' as app;
import 'package:pdfmate/pdf_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots onboarding home settings and lifecycle', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final skip = find.text('Skip');
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    expect(find.text('PDFMate Beta'), findsOneWidget);
    expect(find.text('Scan document'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Auto-save a copy to Downloads'), findsOneWidget);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 250));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Android Downloads and Gallery writes succeed', (tester) async {
    final service = PdfService();
    final temp = await getTemporaryDirectory();

    final pdfFile = File('${temp.path}/pdfmate_storage_smoke.pdf');
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (_) => pw.Center(child: pw.Text('PDFMate storage smoke')),
      ),
    );
    await pdfFile.writeAsBytes(await doc.save(), flush: true);

    final downloadsResult = await service.savePdfToDownloads(pdfFile);
    expect(downloadsResult, isNotEmpty);

    final jpgFile = File('${temp.path}/pdfmate_storage_smoke.jpg');
    final image = img.Image(width: 32, height: 32);
    await jpgFile.writeAsBytes(img.encodeJpg(image), flush: true);

    final galleryResult = await service.saveJpgToGallery(jpgFile);
    expect(galleryResult, isNotEmpty);
  });
}
