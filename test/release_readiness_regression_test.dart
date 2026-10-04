import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfmate/file_store.dart';
import 'package:pdfmate/signature_store.dart';
import 'package:pdfmate/pdf_service.dart';
import 'package:pdfmate/advanced_split_screen.dart';
import 'package:pdfmate/page_organizer_screen.dart';
import 'package:pdfmate/compression_screen.dart';
import 'package:pdfmate/signature_placement_screen.dart';
import 'package:pdfmate/pdf_name_dialog.dart';
import 'package:pdfmate/removed_pdfs_screen.dart';

class _PasswordService extends PdfService {
  final deleted = <String>[];
  final passwords = <String?>[];
  @override Future<File?> pickPdfFile() async => File('/tmp/protected.pdf');
  @override Future<int> pageCount(File file, {String? password}) async {
    passwords.add(password);
    throw StateError(password == null ? 'PDF password required' : 'incorrect password');
  }
  @override Future<List<PdfPageInfo>> pageInfos(File file, {String? password}) async =>
    throw StateError('PDF password required');
  @override Future<File> decryptToTemporary(File file, String password) async {
    passwords.add(password); throw StateError('incorrect password');
  }
  @override Future<void> secureDeleteTemporary(File? file) async {
    if (file != null) deleted.add(file.path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('removed records preserve name date favorite and restore after a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('removed_restore_');
    try {
      final file = await File('${root.path}/document.pdf').writeAsString('original');
      final record = PdfRecord(path: file.path, name: 'My invoice', createdAt: DateTime(2020), favorite: true);
      await PdfFileStore().add(record);
      await PdfFileStore().removeFromLibrary(file.path);
      final restarted = PdfFileStore();
      final removed = (await restarted.loadRemoved()).single;
      expect(removed.toJson(), record.toJson());
      await restarted.restoreRemoved(removed);
      expect((await restarted.load()).single.toJson(), record.toJson());
      expect(await restarted.loadRemoved(), isEmpty);
      expect(await file.readAsString(), 'original');
    } finally { await root.delete(recursive: true); }
  });
  test('legacy hidden records can be restored without a removed-record manifest', () async {
    final root = await Directory.systemTemp.createTemp('legacy_removed_');
    try {
      final file = await File('${root.path}/legacy.pdf').writeAsString('legacy');
      SharedPreferences.setMockInitialValues({'pdfmate_hidden_files_v1': [file.path]});
      final record = (await PdfFileStore().loadRemoved()).single;
      await PdfFileStore().restoreRemoved(record);
      expect((await PdfFileStore().load()).single.name, 'legacy.pdf');
    } finally { await root.delete(recursive: true); }
  });
  test('signature backup restores into fresh storage and repeated import is idempotent', () async {
    final root = await Directory.systemTemp.createTemp('signature_backup_');
    final target = await Directory.systemTemp.createTemp('signature_restore_');
    try {
      final store = SignatureStore(directoryProvider: () async => root);
      final bytes = Uint8List.fromList(img.encodePng(img.Image(width: 100, height: 40)));
      await store.save('Owner', bytes);
      final backup = await store.exportBackup();
      final restored = SignatureStore(directoryProvider: () async => target);
      expect(await restored.restoreBackup(backup), 1);
      expect(await restored.restoreBackup(backup), 0);
      expect(await (await restored.load()).single.file.readAsBytes(), bytes);
      expect((await restored.load()).single.name, 'Owner');
      final invalid = jsonDecode(utf8.decode(backup)) as Map<String, dynamic>;
      final entries = invalid['signatures'] as List;
      entries.add({'file': '../outside.png', 'name': 'Owner', 'png': base64Encode(bytes)});
      final empty = SignatureStore(directoryProvider: () async => Directory('${target.path}/fresh'));
      await expectLater(empty.restoreBackup(Uint8List.fromList(utf8.encode(jsonEncode(invalid)))), throwsFormatException);
      expect(await empty.load(), isEmpty);
    } finally { await root.delete(recursive: true); await target.delete(recursive: true); }
  });
  test('malformed and oversized signature backups fail before publication', () async {
    final root = await Directory.systemTemp.createTemp('bad_backup_');
    try {
      final store = SignatureStore(directoryProvider: () async => root);
      await expectLater(store.restoreBackup(Uint8List(SignatureStore.maxBackupBytes + 1)), throwsFormatException);
      await expectLater(store.restoreBackup(Uint8List.fromList(utf8.encode('{"version":1}'))), throwsFormatException);
      expect(await store.load(), isEmpty);
    } finally { await root.delete(recursive: true); }
  });
  for (final tool in ['Split', 'Organizer', 'Compression', 'Sign']) {
    testWidgets('$tool generic password failure retries and cancels without disposed controllers', (tester) async {
      final service = _PasswordService();
      final Widget screen = switch (tool) {
        'Split' => AdvancedSplitScreen(service: service),
        'Organizer' => PageOrganizerScreen(service: service),
        'Compression' => CompressionScreen(service: service),
        _ => SignaturePlacementScreen(service: service),
      };
      await tester.pumpWidget(MaterialApp(home: screen));
      final choose = (tool == 'Split' || tool == 'Compression') ? 'Choose' : 'Choose PDF';
      await tester.tap(find.text(choose));
      await tester.pump(); await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(TextField), findsWidgets);
      final input = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(input, 'bad');
      await tester.tap(find.text('Open'));
      await tester.pump(); await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.passwords, contains('bad'));
      expect(service.deleted, contains('/tmp/protected.pdf'));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('rename dialog survives immediate replacement and preserves entered name', (tester) async {
    String? name;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        name = await askPdfName(context, initialName: 'Original');
        if (context.mounted) await askPdfName(context, initialName: name ?? 'Original');
      }, child: const Text('Rename file'))))));
    await tester.tap(find.text('Rename file')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' Invoice ');
    await tester.tap(find.text('Rename')); await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(name, 'Invoice');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Invoice');
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Removed PDFs screen restores a stored record', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = (await tester.runAsync(() => Directory.systemTemp.createTemp('restore_ui_')))!;
    try {
      await tester.runAsync(() async {
        final file = await File('${root.path}/invoice.pdf').writeAsString('invoice');
        await PdfFileStore().add(PdfRecord(path: file.path, name: 'Invoice', createdAt: DateTime(2020)));
        await PdfFileStore().removeFromLibrary(file.path);
      });
      await tester.pumpWidget(MaterialApp(home: RemovedPdfsScreen(store: PdfFileStore())));
      await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
      await tester.pumpAndSettle();
      expect(find.text('Invoice'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Restore'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('No removed PDFs to restore.'), findsOneWidget);
      final records = await tester.runAsync(() => PdfFileStore().load());
      expect(records!.single.name, 'Invoice');
    } finally { await tester.pumpWidget(const SizedBox()); await tester.runAsync(() => root.delete(recursive: true)); }
  });
}
