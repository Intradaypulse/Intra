import 'dart:io';
import 'dart:typed_data';
import 'unicode_overlay_cases.dart';
import 'deep_audit_cases.dart';
import 'performance_cases.dart';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:pdfmate/live_scanner_screen.dart';
import 'package:pdfmate/file_store.dart';
import 'package:pdfmate/removed_pdfs_screen.dart';
import 'package:pdfmate/signature_store.dart';
import 'package:pdfmate/main.dart' as app;
import 'package:pdfmate/pdf_service.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  registerUnicodeOverlayCases();
  registerDeepAuditCases();
  registerPerformanceCases();

  testWidgets('Android removed PDF listing restores bytes and metadata through the screen', (tester) async {
    final root = await getApplicationDocumentsDirectory();
    final source = File('${root.path}/qa_restore.pdf');
    final store = PdfFileStore();
    final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('Restore invoice')));
    await source.writeAsBytes(await doc.save());
    final bytes = await source.readAsBytes();
    final record = PdfRecord(path: source.path, name: 'Restore invoice', createdAt: DateTime(2020), favorite: true);
    try {
      await store.add(record);
      await store.removeFromLibrary(source.path);
      expect((await PdfFileStore().loadRemoved()).singleWhere((item) => item.path == source.path).toJson(), record.toJson());
      await tester.pumpWidget(MaterialApp(home: RemovedPdfsScreen(store: PdfFileStore())));
      await _waitFor(tester, find.text('Restore invoice'));
      await tester.tap(find.text('Restore'));
      await _waitFor(tester, find.text('PDF restored to My PDFs.'));
      expect((await PdfFileStore().load()).singleWhere((item) => item.path == source.path).toJson(), record.toJson());
      expect(await source.readAsBytes(), bytes);
    } finally {
      await store.remove(source.path);
      if (await source.exists()) await source.delete();
    }
  });

  testWidgets('Android signature backup exports to Downloads and restores without duplicates', (tester) async {
    final root = await getApplicationDocumentsDirectory();
    final original = Directory('${root.path}/qa_signature_original');
    final restored = Directory('${root.path}/qa_signature_restored');
    try {
      final store = SignatureStore(directoryProvider: () async => original);
      final bytes = Uint8List.fromList(img.encodePng(img.Image(width: 100, height: 40)));
      await store.save('Owner', bytes);
      final backup = await store.exportBackup();
      expect(await PdfService().exportSignatureBackup(backup), isNotEmpty);
      final target = SignatureStore(directoryProvider: () async => restored);
      expect(await target.restoreBackup(backup), 1);
      expect(await target.restoreBackup(backup), 0);
      expect(await (await target.load()).single.file.readAsBytes(), bytes);
    } finally {
      if (await original.exists()) await original.delete(recursive: true);
      if (await restored.exists()) await restored.delete(recursive: true);
    }
  });

  testWidgets('camera still JPEG is preserved and converts to a one-page PDF', (tester) async {
    final cameras = await availableCameras();
    expect(cameras, isNotEmpty);
    final controller = CameraController(cameras.first, ResolutionPreset.max, enableAudio: false);
    File? photo;
    File? output;
    try {
      await controller.initialize();
      final captured = await controller.takePicture();
      photo = File(captured.path);
      final original = await photo.readAsBytes();
      final decoded = img.decodeJpg(original);
      expect(decoded, isNotNull);
      expect(decoded!.width, greaterThan(100));
      expect(decoded.height, greaterThan(100));
      final service = PdfService();
      final uri = await service.saveJpgToGallery(photo);
      expect(uri, isNotEmpty);
      expect(await photo.readAsBytes(), original);
      output = await service.createScannedPdfFromFiles([photo.path]);
      expect(await service.pageCount(output), 1);
      expect(await photo.readAsBytes(), original);
    } finally {
      await controller.dispose();
      if (photo != null && await photo.exists()) await photo.delete();
      if (output != null && await output.exists()) await output.delete();
    }
  });

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

      expect(find.text('ScanLumo Beta'), findsOneWidget);
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
      expect(find.text('ScanLumo Beta'), findsOneWidget);
      debugPrint('SMOKE: lifecycle checks complete');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets('image PDFs preserve tall and wide aspect ratios and clean up failed jobs', (tester) async {
    final root = await Directory.systemTemp.createTemp('pdfmate_image_ratio_');
    final temp = await Directory('${root.path}/temp').create();
    final docs = await Directory('${root.path}/docs').create();
    final service = PdfService(documentsDirectoryProvider: () async => docs,
      temporaryDirectoryProvider: () async => temp);
    final engine = Pdf();
    PdfDoc? doc;
    try {
      final tall = File('${root.path}/tall.png');
      final wide = File('${root.path}/wide.png');
      await tall.writeAsBytes(img.encodePng(img.Image(width: 100, height: 400)));
      await wide.writeAsBytes(img.encodePng(img.Image(width: 400, height: 100)));
      final output = await service.imageFilesToPdf([tall, wide]);
      doc = await engine.open(FileSource(output));
      expect(doc.pageCount, 2);
      expect(doc.pages[0].effectiveWidth / doc.pages[0].effectiveHeight, closeTo(.25, .001));
      expect(doc.pages[1].effectiveWidth / doc.pages[1].effectiveHeight, closeTo(4, .001));
      final invalid = File('${root.path}/bad.png');
      await invalid.writeAsString('invalid image');
      await expectLater(service.imageFilesToPdf([tall, invalid]), throwsA(anything));
      expect(await temp.list().toList(), isEmpty);
      expect(await docs.list().toList(), hasLength(1));
    } finally {
      await doc?.dispose();
      await engine.dispose();
      await root.delete(recursive: true);
    }
  });

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
