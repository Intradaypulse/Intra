import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdfmate/pdf_service.dart';
import 'package:pdfmate/signature_placement_screen.dart';
import 'package:pdfmate/file_store.dart';
import 'package:pdfmate/scan_draft_store.dart';
import 'package:pdfmate/signature_screen.dart';
import 'package:pdfmate/signature_store.dart';

class _PlacementService extends PdfService {
  _PlacementService(this.source, this.infos, this.preview);
  final File source;
  final List<PdfPageInfo> infos;
  final Uint8List preview;
  @override Future<File?> pickPdfFile() async => source;
  @override Future<List<PdfPageInfo>> pageInfos(File source, {String? password}) async => infos;
  @override Future<PdfRect> pageVisibleBox(File source, int page, {String? password}) async =>
    PdfRect(x: 0, y: 0, width: infos.single.width, height: infos.single.height);
  @override Future<Uint8List?> renderPage(File source, int page, {String? password,
    int width = 1000, PdfOperationControl? control}) async => preview;
  @override Future<void> secureDeleteTemporary(File? file) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('removing from My PDFs preserves storage and stays removed after recovery', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('remove_pdf_');
    try {
      final file = await File('${root.path}/original.pdf').writeAsBytes([1, 2, 3]);
      final record = PdfRecord(path: file.path, name: 'original.pdf', createdAt: DateTime.now());
      await PdfFileStore().add(record);
      await PdfFileStore().removeFromLibrary(file.path);
      expect(await file.readAsBytes(), [1, 2, 3]);
      final restarted = PdfFileStore();
      await restarted.recoverMissing([record]);
      expect(await restarted.load(), isEmpty);
      await restarted.add(record);
      expect((await restarted.load()).single.path, file.path);
    } finally { await root.delete(recursive: true); }
  });
  test('JPG export retry preserves original bytes and skips confirmed copies', () async {
    final root = await Directory.systemTemp.createTemp('gallery_retry_');
    try {
      final store = ScanDraftStore(directoryProvider: () async => root);
      final bytes = Uint8List.fromList(img.encodeJpg(img.Image(width: 240, height: 320)));
      final first = await store.append(bytes);
      final second = await store.append(bytes);
      final calls = <String>[];
      await expectLater(store.exportJpgs([first.path, second.path], (file) async {
        calls.add(file.path);
        if (file.path == second.path) throw const FileSystemException('Gallery unavailable');
        expect(await file.readAsBytes(), bytes);
        return 'content://gallery/first';
      }), throwsA(isA<FileSystemException>()));
      final restarted = ScanDraftStore(directoryProvider: () async => root);
      await restarted.exportJpgs([first.path, second.path], (file) async {
        calls.add(file.path);
        expect(await file.readAsBytes(), bytes);
        return 'content://gallery/second';
      });
      expect(calls, [first.path, second.path, second.path]);
      expect(await first.readAsBytes(), bytes);
      expect(await second.readAsBytes(), bytes);
    } finally { await root.delete(recursive: true); }
  });
  testWidgets('two fingers anywhere on the page enlarge shrink and rotate the signature', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = await Directory.systemTemp.createTemp('signature_gesture_');
    try {
      final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('Sign here')));
      final source = await File('${root.path}/page.pdf').writeAsBytes(await doc.save());
      final infos = await tester.runAsync(() => PdfService().pageInfos(source));
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 100, height: 40)));
      await tester.pumpWidget(MaterialApp(home: SignaturePlacementScreen(
        service: _PlacementService(source, infos!, png), initialSignature: png)));
      await tester.tap(find.text('Choose PDF'));
      await tester.pumpAndSettle();
      final page = tester.getRect(find.byKey(const ValueKey('signature-page-gestures')));
      final center = Offset(page.center.dx, page.top + page.height * .25);
      double size() => tester.widget<Slider>(find.byType(Slider).at(0)).value;
      Future<void> pinch(double from, double to) async {
        final left = await tester.startGesture(center - Offset(from, 0), pointer: 1);
        final right = await tester.startGesture(center + Offset(from, 0), pointer: 2);
        await tester.pump();
        await left.moveTo(center - Offset(to, 0));
        await right.moveTo(center + Offset(to, 0));
        await tester.pump();
        await left.up(); await right.up(); await tester.pump();
      }
      final original = size();
      await pinch(25, 65);
      expect(size(), greaterThan(original));
      final enlarged = size();
      await pinch(65, 20);
      expect(size(), lessThan(enlarged));
      final left = await tester.startGesture(center - const Offset(45, 0), pointer: 1);
      final right = await tester.startGesture(center + const Offset(45, 0), pointer: 2);
      await tester.pump();
      await left.moveTo(center - const Offset(0, 45));
      await right.moveTo(center + const Offset(0, 45));
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider).at(1)).value.abs(), greaterThan(20));
      await left.up(); await right.up();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await root.delete(recursive: true);
    }
  });
  testWidgets('explicit signature Save persists PNG without leaving drawing screen', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = await Directory.systemTemp.createTemp('signature_ui_');
    try {
      await tester.pumpWidget(MaterialApp(home: SignatureScreen(
        store: SignatureStore(directoryProvider: () async => root))));
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
      final canvas = tester.getRect(find.byType(Signature));
      await tester.dragFrom(canvas.center, const Offset(90, 30));
      await tester.runAsync(() async {
        await tester.tap(find.text('Save signature'));
        await tester.pump();
      });
      await tester.pumpAndSettle();
      final saved = await tester.runAsync(() => SignatureStore(directoryProvider: () async => root).load());
      expect(saved, hasLength(1));
      final bytes = await tester.runAsync(() => saved!.single.file.readAsBytes());
      expect(img.decodePng(bytes!), isNotNull);
      expect(find.text('Draw signature'), findsOneWidget);
      expect(find.text('Signature saved for reuse.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await root.delete(recursive: true);
    }
  });
}
