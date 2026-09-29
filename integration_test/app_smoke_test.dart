import 'dart:io';
import 'unicode_overlay_cases.dart';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
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

  registerUnicodeOverlayCases();

  testWidgets(
    'app boots, settings and camera lifecycle work',
    (tester) async {
      debugPrint('SMOKE: launching app');
      await app.main();
      await _settle(tester);

      final skip = find.text('Skip');
      if (skip.evaluate().isNotEmpty) {
        await tester.tap(skip);
        await _settle(tester);
      }

      expect(find.text('PDFMate Beta'), findsOneWidget);
      expect(find.text('Scan document'), findsOneWidget);

      debugPrint('SMOKE: home ready, opening settings');
      await tester.tap(find.byTooltip('Settings'));
      await _settle(tester);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Auto-save a copy to Downloads'), findsOneWidget);

      debugPrint('SMOKE: settings pause/resume');
      // A paused binding does not schedule frames. Awaiting pump before resumed
      // deadlocks a live integration test even though the application is healthy.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);

      expect(find.text('Settings'), findsOneWidget);
      await tester.pageBack();
      await _settle(tester);

      debugPrint('SMOKE: opening camera');
      await tester.tap(find.text('Scan document'));
      await tester.pump();
      // Keep an arbitrary physical camera scene from triggering auto-capture
      // while this test is checking preview, torch and lifecycle recovery.
      final autoCapture = find.byType(Switch);
      await _waitFor(tester, autoCapture);
      if (tester.widget<Switch>(autoCapture).value) {
        await tester.tap(autoCapture);
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(LiveScannerScreen), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      await _waitFor(tester, find.byType(CameraPreview));
      if (const bool.fromEnvironment('PDFMATE_PHYSICAL_QA')) {
        await tester.tap(find.byTooltip('Torch'));
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester
              .widget<CameraPreview>(find.byType(CameraPreview))
              .controller
              .value
              .flashMode,
          FlashMode.torch,
        );
        await tester.tap(find.byTooltip('Torch'));
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester
              .widget<CameraPreview>(find.byType(CameraPreview))
              .controller
              .value
              .flashMode,
          FlashMode.off,
        );
      }
      debugPrint('SMOKE: camera pause/resume');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      await _waitFor(tester, find.byType(CameraPreview));

      await tester.pageBack();
      await _settle(tester);
      expect(find.text('PDFMate Beta'), findsOneWidget);
      debugPrint('SMOKE: lifecycle checks complete');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets('Android scoped-storage exports return confirmed destinations', (
    tester,
  ) async {
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 30),
  );
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsOneWidget);
}
