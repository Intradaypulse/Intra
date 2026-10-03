import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfmate/pdf_service.dart';
import 'package:pdfmate/scan_draft_store.dart';
import 'package:pdfmate/advanced_split_screen.dart';
import 'package:pdfmate/page_organizer_screen.dart';

class SparseOcrService extends PdfService {
  SparseOcrService(this.readable);
  final Set<int> readable;
  final visited = <int>[];
  @override
  Future<int> pageCount(File source, {String? password}) async => 7;
  @override
  Future<OcrPagePreview> recognizePage(File source, int pageIndex, {
    String? password, TextRecognitionScript? script, PdfOperationControl? control,
  }) async {
    control?.check();
    visited.add(pageIndex);
    final text = readable.contains(pageIndex) ? 'Invoice 12345' : '';
    return OcrPagePreview(bytes: Uint8List(0), width: 600, height: 800,
      script: TextRecognitionScript.latin,
      text: RecognizedText(text: text, blocks: [TextBlock(text: text,
        boundingBox: const Rect.fromLTWH(0, 0, 100, 20), cornerPoints: [],
        recognizedLanguages: [], lines: [TextLine(text: text, elements: [],
          boundingBox: const Rect.fromLTWH(0, 0, 100, 20), cornerPoints: [],
          recognizedLanguages: [], confidence: null, angle: null)])]));
  }
}

class ProtectedToolService extends PdfService {
  var writes = 0;
  @override
  Future<File?> pickPdfFile() async => File('/tmp/protected.pdf');
  @override
  Future<int> pageCount(File source, {String? password}) async => 1;
  @override
  bool wasProtected(File file) => true; // Owner-only encryption: no password prompt.
  @override
  Future<Uint8List?> renderPage(File source, int page, {String? password,
    int width = 1000, PdfOperationControl? control}) async => null;
  @override
  Future<void> secureDeleteTemporary(File? file) async {}
  @override
  Future<List<File>> splitRanges(File source, List<List<int>> ranges, {String? password}) async {
    writes++; throw StateError('Stop after observing authorized write');
  }
  @override
  Future<File> organizePdf(File source, {required List<int> pageOrder,
    required Map<int, int> rotations, String? password}) async {
    writes++; throw StateError('Stop after observing authorized write');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Auto OCR checks unsampled pages when cover middle and end are blank', () async {
    final service = SparseOcrService({1});
    expect(await service.detectOcrScript(File('scan.pdf')), TextRecognitionScript.latin);
    expect(service.visited, [0, 3, 6, 1]);
  });
  test('Auto OCR exhausts an entirely blank document once and remains cancellable', () async {
    final service = SparseOcrService({});
    await expectLater(service.detectOcrScript(File('blank.pdf')), throwsStateError);
    expect(service.visited.toSet(), {0, 1, 2, 3, 4, 5, 6});
    expect(service.visited.length, 7);
    final cancelled = PdfOperationControl()..cancel();
    await expectLater(service.detectOcrScript(File('blank.pdf'), control: cancelled),
      throwsA(isA<PdfOperationCancelled>()));
    expect(service.visited.length, 7);
  });
  test('scan reservation survives every publication boundary with one destination', () async {
    final root = await Directory.systemTemp.createTemp('reserved_scan_');
    try {
      final store = ScanDraftStore(directoryProvider: () async => root);
      final page = await store.append(Uint8List.fromList([1]));
      final pages = [page.path];
      final target = await store.reserveOutput(pages);
      expect(await store.completedOutput(pages), isNull);
      await File('${target.path}.pending').writeAsString('partial');
      final restarted = ScanDraftStore(directoryProvider: () async => root);
      expect((await restarted.reserveOutput(pages)).path, target.path);
      await PdfService(documentsDirectoryProvider: () async => root).recoverableOutputs();
      expect(await File('${target.path}.pending').exists(), isFalse);
      await target.writeAsString('complete'); // PDF publication, no post-save receipt needed.
      expect((await restarted.completedOutput(pages))!.path, target.path);
      // Crash during receipt publication is also stable because the name is session-derived.
      await File('${page.parent.path}/output.txt').rename('${page.parent.path}/output.txt.pending');
      await restarted.recover();
      expect((await restarted.reserveOutput(pages)).path, target.path);
      expect((await restarted.completedOutput(pages))!.path, target.path);
      expect((await root.list().where((f) => f.path.endsWith('.pdf')).toList()).length, 1);
      await restarted.discard(pages);
      expect(await target.exists(), isTrue);
    } finally { await root.delete(recursive: true); }
  });
  for (final organizer in [false, true]) {
    testWidgets('${organizer ? 'Organizer' : 'Split'} requires consent for owner-only protection', (tester) async {
      final service = ProtectedToolService();
      await tester.pumpWidget(MaterialApp(home: organizer
        ? PageOrganizerScreen(service: service) : AdvancedSplitScreen(service: service)));
      await tester.tap(find.text(organizer ? 'Choose PDF' : 'Choose'));
      await tester.pumpAndSettle();
      if (!organizer) {
        await tester.tap(find.widgetWithText(CheckboxListTile, '1'));
      }
      final save = find.text(organizer ? 'Save' : 'Split PDF');
      await tester.ensureVisible(save); await tester.tap(save); await tester.pumpAndSettle();
      expect(find.text('Create an unprotected copy?'), findsOneWidget);
      expect(service.writes, 0);
      await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
      expect(service.writes, 0);
      await tester.tap(save); await tester.pumpAndSettle();
      await tester.tap(find.text('Create unprotected copy')); await tester.pumpAndSettle();
      expect(service.writes, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
