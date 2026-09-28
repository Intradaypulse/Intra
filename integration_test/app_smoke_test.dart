import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfmate/live_scanner_screen.dart';
import 'package:pdfmate/main.dart' as app;
import 'package:pdfmate/pdf_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots, settings and camera lifecycle work', (tester) async {
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
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan document'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(LiveScannerScreen), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('PDFMate Beta'), findsOneWidget);
  });

  testWidgets('Android scoped-storage exports return confirmed destinations',
      (tester) async {
    final service = PdfService();
    final tmp = await getTemporaryDirectory();

    final pdfFile = File(
      '${tmp.path}/pdfmate_integration_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (_) => pw.Center(child: pw.Text('PDFMate integration export')),
      ),
    );
    await pdfFile.writeAsBytes(await pdf.save(), flush: true);

    final bitmap = img.Image(width: 16, height: 16);
    final jpgFile = File(
      '${tmp.path}/pdfmate_integration_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await jpgFile.writeAsBytes(img.encodeJpg(bitmap), flush: true);

    try {
      final download = await service.savePdfToDownloads(pdfFile);
      final gallery = await service.saveJpgToGallery(jpgFile);

      expect(download.trim(), isNotEmpty);
      expect(gallery.trim(), isNotEmpty);
    } finally {
      if (await pdfFile.exists()) await pdfFile.delete();
      if (await jpgFile.exists()) await jpgFile.delete();
    }
  });
}
