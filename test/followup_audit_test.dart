import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfmate/pdf_service.dart';
import 'package:pdfmate/file_store.dart';
import 'package:pdfmate/scan_draft_store.dart';
import 'package:pdfmate/ocr_screen.dart';

class PickingService extends PdfService {
  PickingService(Directory docs, Directory temp, this.source)
    : super(documentsDirectoryProvider: () async => docs,
        temporaryDirectoryProvider: () async => temp);
  final File source;
  @override
  Future<File?> pickPdfFile() async => source;
}

class FailingSplitService extends PdfService {
  FailingSplitService(Directory docs)
    : super(documentsDirectoryProvider: () async => docs);
  final attempted = <String>[];
  final originalError = StateError('extraction failed');
  var parts = 0;
  @override
  Future<int> pageCount(File source, {String? password}) async => 3;
  @override
  Future<void> writeSplitPart(Pdf engine, File source, File output,
      List<int> pages, {String? password}) async {
    await output.writeAsString('partial');
    if (++parts == 2) throw originalError;
  }
  @override
  Future<void> deleteFailedSplitOutput(File file) async {
    attempted.add(file.path);
    if (attempted.length == 1) throw const FileSystemException('delete failed');
    await super.deleteFailedSplitOutput(file);
  }
}

class OwnerOcrService extends PdfService {
  final passwords = <String?>[];
  var writes = 0;
  @override
  Future<File?> pickPdfFile() async => File('/tmp/owner-protected.pdf');
  @override
  Future<int> pageCount(File source, {String? password}) async => 1;
  @override
  Future<bool> hasDigitalSignatures(File source, {String? password}) async => false;
  @override
  Future<void> secureDeleteTemporary(File? file) async {}
  @override
  Future<void> checkOcrPermission(File source, {String? password}) async {
    passwords.add(password);
    if (password == null) throw PlatformException(code: 'OCR_OWNER_PASSWORD_REQUIRED');
    if (password != 'owner-secret') throw PlatformException(code: 'OCR_WRONG_PASSWORD');
  }
  @override
  Future<TextRecognitionScript> detectOcrScript(File source, {
    String? password, PdfOperationControl? control,
  }) async => TextRecognitionScript.latin;
  @override
  Future<File> makeSearchablePdf(File source, {
    TextRecognitionScript script = TextRecognitionScript.latin,
    String? password, PdfOperationControl? control, bool tableRows = false,
  }) async {
    expect(password, 'owner-secret');
    writes++;
    return File('/tmp/searchable.pdf');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, docs, temp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('followup_audit_');
    docs = await Directory('${root.path}/docs').create();
    temp = await Directory('${root.path}/temp').create();
  });
  tearDown(() async { await root.delete(recursive: true); });

  Future<File> fixture() async {
    final pdf = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('Protected invoice')));
    return File('${docs.path}/source.pdf').writeAsBytes(await pdf.save());
  }

  test('scan reorder and subsequent capture survive restart and removal', () async {
    final store = ScanDraftStore(directoryProvider: () async => docs);
    final a = await store.append(Uint8List.fromList([1]));
    final b = await store.append(Uint8List.fromList([2]));
    final c = await store.append(Uint8List.fromList([3]));
    await store.persistOrder([c.path, a.path, b.path]);
    final d = await store.append(Uint8List.fromList([4]));
    final restarted = ScanDraftStore(directoryProvider: () async => docs);
    expect((await restarted.recover()).single, [c.path, a.path, b.path, d.path]);
    await store.removePage([c.path, b.path, d.path], a.path);
    expect((await restarted.recover()).single, [c.path, b.path, d.path]);
    await store.removePage([b.path, d.path], c.path);
    await store.removePage([d.path], b.path);
    await store.removePage([], d.path);
    expect(await restarted.recover(), isEmpty);
  });

  test('legacy drafts and unpublished final capture retain all pages', () async {
    final store = ScanDraftStore(directoryProvider: () async => docs);
    final page = await store.append(Uint8List.fromList([1]));
    await File('${page.parent.path}/order.json').delete();
    expect((await store.recover()).single, [page.path]);
    await store.persistOrder([page.path]);
    final orphan = await File('${page.parent.path}/z.jpg').writeAsBytes([2]);
    expect((await store.recover()).single, [page.path, orphan.path]);
  });

  test('recovery preserves existing date name favorite and adds only missing paths', () async {
    final a = await File('${docs.path}/a.pdf').writeAsString('a');
    final b = await File('${docs.path}/b.pdf').writeAsString('b');
    final store = PdfFileStore();
    final original = PdfRecord(path: a.path, name: 'Original name',
      createdAt: DateTime(2020), favorite: true);
    await store.addMany([original]);
    final recovered = [
      PdfRecord(path: a.path, name: 'a.pdf', createdAt: DateTime(2026)),
      PdfRecord(path: b.path, name: 'b.pdf', createdAt: DateTime(2026)),
    ];
    await store.recoverMissing(recovered);
    await store.recoverMissing(recovered);
    final records = await store.load();
    expect(records, hasLength(2));
    expect(records.singleWhere((r) => r.path == a.path).toJson(), original.toJson());
  });

  test('unsaved compression is excluded from recovery; explicit Save publishes it', () async {
    final source = await fixture();
    final service = PdfService(documentsDirectoryProvider: () async => docs,
      temporaryDirectoryProvider: () async => temp);
    final result = await service.compressAdvanced(source, CompressionPreset.balanced);
    expect(service.isManagedTemporaryFile(result.file), isTrue);
    final restarted = PdfService(documentsDirectoryProvider: () async => docs,
      temporaryDirectoryProvider: () async => temp);
    expect((await restarted.recoverableOutputs()).map((f) => f.path), [source.path]);
    final published = await service.publishCompressionPreview(result.file);
    expect(await result.file.exists(), isFalse);
    expect(await service.pageCount(published), 1);
    expect((await restarted.recoverableOutputs()).map((f) => f.path), contains(published.path));
    expect(await temp.list().toList(), isEmpty);
  });

  test('failed compression publication retains preview for retry', () async {
    final source = await fixture();
    final service = PdfService(documentsDirectoryProvider: () async => docs,
      temporaryDirectoryProvider: () async => temp);
    final result = await service.compressAdvanced(source, CompressionPreset.balanced);
    await docs.delete(recursive: true); // Destination unavailable during Save.
    await expectLater(service.publishCompressionPreview(result.file), throwsA(isA<FileSystemException>()));
    expect(await result.file.exists(), isTrue);
    await docs.create();
    final saved = await service.publishCompressionPreview(result.file);
    expect(await service.pageCount(saved), 1);
    expect(await result.file.exists(), isFalse);
  });

  test('extract protected text retries wrong password without re-picking', () async {
    final source = await fixture();
    final base = PdfService(documentsDirectoryProvider: () async => docs,
      temporaryDirectoryProvider: () async => temp);
    final encrypted = await base.protectPdfAdvanced(source,
      ownerPassword: 'owner-secret', userPassword: 'open-secret');
    final service = PickingService(docs, temp, encrypted);
    final prompts = <bool>[];
    final result = await service.extractPdfTextToFile(requestPassword: (wrong) async {
      prompts.add(wrong);
      return prompts.length == 1 ? 'bad' : 'open-secret';
    });
    expect(prompts, [false, true]);
    expect(result!.$2, contains('Protected invoice'));
    await service.secureDeleteTemporary(result.$1);
    expect(await temp.list().toList(), isEmpty);
  });

  test('extract password cancellation cleans all owned picker and text files', () async {
    final source = await fixture();
    final base = PdfService(documentsDirectoryProvider: () async => docs,
      temporaryDirectoryProvider: () async => temp);
    final encrypted = await base.protectPdfAdvanced(source,
      ownerPassword: 'owner-secret', userPassword: 'open-secret');
    final service = PickingService(docs, temp, encrypted);
    expect(await service.extractPdfTextToFile(requestPassword: (_) async => null), isNull);
    expect(await temp.list().toList(), isEmpty);
    expect(await encrypted.exists(), isTrue);
  });

  test('split attempts all cleanup, retains original error and releases pending registrations', () async {
    final service = FailingSplitService(docs);
    await expectLater(service.splitEveryN(File('source.pdf'), 1),
      throwsA(same(service.originalError)));
    expect(service.attempted, hasLength(2));
    expect(await File(service.attempted[1]).exists(), isFalse);
    expect(await File(service.attempted[0]).exists(), isTrue);
    await PdfService(documentsDirectoryProvider: () async => docs).recoverableOutputs();
    expect(await docs.list().toList(), isEmpty);
  });

  for (final cancel in [false, true]) {
    testWidgets('owner-only OCR password flow cancel=$cancel', (tester) async {
      final service = OwnerOcrService();
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
        TextButton(onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => OcrScreen(service: service))),
          child: const Text('Launch')))));
      await tester.tap(find.text('Launch')); await tester.pumpAndSettle();
      await tester.tap(find.text('Choose')); await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Make searchable'));
      await tester.tap(find.text('Make searchable')); await tester.pumpAndSettle();
      expect(find.text('Owner password required'), findsOneWidget);
      expect(service.writes, 0);
      if (cancel) {
        await tester.enterText(find.byType(TextField), 'bad');
        await tester.tap(find.text('Open')); await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
        expect(service.writes, 0);
        await tester.ensureVisible(find.text('Make searchable'));
        await tester.tap(find.text('Make searchable')); await tester.pumpAndSettle();
        expect(service.passwords, [null, 'bad', null]);
        await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
      } else {
        await tester.enterText(find.byType(TextField), 'bad');
        await tester.tap(find.text('Open')); await tester.pumpAndSettle();
        expect(find.text('Wrong owner password. Try again'), findsOneWidget);
        expect(service.writes, 0);
        await tester.enterText(find.byType(TextField), 'owner-secret');
        await tester.tap(find.text('Open')); await tester.pumpAndSettle();
        expect(service.passwords, [null, 'bad', 'owner-secret']);
        expect(service.writes, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
