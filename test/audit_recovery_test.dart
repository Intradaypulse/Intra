import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/scan_draft_store.dart';
import 'package:pdfmate/pdf_service.dart';
import 'package:pdfmate/signature_geometry.dart';
import 'package:pdfmate/output_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('capture drafts survive restart and discard never deletes completed PDF', () async {
    final root = await Directory.systemTemp.createTemp('scan_recovery_');
    try {
      final store = ScanDraftStore(directoryProvider: () async => root);
      final page = await store.append(Uint8List.fromList([1, 2, 3]));
      final output = await File('${root.path}/Scan.pdf').writeAsString('complete');
      await store.rememberOutput([page.path], output);
      final partial = await File('${page.parent.path}/failed.jpg.pending').writeAsString('partial capture');
      final restarted = ScanDraftStore(directoryProvider: () async => root);
      final drafts = await restarted.recover();
      expect(drafts.single, [page.path]);
      expect(await partial.exists(), isFalse);
      expect((await restarted.completedOutput(drafts.single))!.path, output.path);
      await restarted.discard(drafts.single);
      expect(await page.exists(), isFalse);
      expect(await output.exists(), isTrue);
      expect(await restarted.recover(), isEmpty);
    } finally { await root.delete(recursive: true); }
  });

  test('recovery discovers complete outputs but excludes partial and secure files', () async {
    final root = await Directory.systemTemp.createTemp('output_recovery_');
    try {
      for (final name in ['Compressed_1.pdf', 'Scan_2.pdf.pending', 'pdfmate_secure_tmp_plain.pdf']) {
        await File('${root.path}/$name').writeAsString('fixture');
      }
      final service = PdfService(documentsDirectoryProvider: () async => root);
      expect((await service.recoverableOutputs()).map((f) => f.uri.pathSegments.last), ['Compressed_1.pdf']);
    } finally { await root.delete(recursive: true); }
  });

  test('signature corners map to bottom-left PDF coordinates for every rotation', () {
    const view = Rect.fromLTWH(10, 20, 100, 40);
    expect(signaturePdfRect(view, 600, 800, 0), const Rect.fromLTWH(10, 740, 100, 40));
    expect(signaturePdfRect(view, 600, 800, 90), const Rect.fromLTWH(20, 10, 40, 100));
    expect(signaturePdfRect(view, 600, 800, 180), const Rect.fromLTWH(490, 20, 100, 40));
    expect(signaturePdfRect(view, 600, 800, 270), const Rect.fromLTWH(540, 690, 40, 100));
  });

  testWidgets('unprotected export requires explicit approval and can be cancelled', (tester) async {
    bool? allowed;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () async { allowed = await confirmUnprotectedOutput(context); }, child: const Text('Edit')))));
    await tester.tap(find.text('Edit')); await tester.pumpAndSettle();
    expect(find.textContaining('Downloads'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(allowed, isFalse);
    await tester.tap(find.text('Edit')); await tester.pumpAndSettle();
    await tester.tap(find.text('Create unprotected copy')); await tester.pumpAndSettle();
    expect(allowed, isTrue);
  });
}
