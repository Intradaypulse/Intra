import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfmate/file_store.dart';
import 'package:pdfmate/pdf_service.dart';
import 'package:pdfmate/scan_temp_session.dart';
import 'package:pdfmate/serial_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PdfService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('pdfmate_safety_');
    service = PdfService(
      documentsDirectoryProvider: () async => root,
      temporaryDirectoryProvider: () async => root,
    );
  });
  tearDown(() async => root.delete(recursive: true));

  test('rename collision preserves both documents', () async {
    final source = await File(
      '${root.path}/source.pdf',
    ).writeAsString('source');
    final existing = await File(
      '${root.path}/existing.pdf',
    ).writeAsString('existing');
    await expectLater(
      service.renamePdf(source, 'existing'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await source.readAsString(), 'source');
    expect(await existing.readAsString(), 'existing');
  });

  test(
    'concurrent renames cannot overwrite the first completed document',
    () async {
      final a = await File('${root.path}/a.pdf').writeAsString('A');
      final b = await File('${root.path}/b.pdf').writeAsString('B');
      final first = service.renamePdf(a, 'target');
      final second = expectLater(
        service.renamePdf(b, 'target'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await (await first).readAsString(), 'A');
      await second;
      expect(await b.readAsString(), 'B');
    },
  );

  test('library retains more than 250 records after an add', () async {
    final store = PdfFileStore();
    final records = <PdfRecord>[];
    for (var i = 0; i < 251; i++) {
      final file = await File('${root.path}/$i.pdf').writeAsString('$i');
      records.add(
        PdfRecord(
          path: file.path,
          name: '$i.pdf',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
    }
    await store.save(records.take(250).toList());
    await store.add(records.last);
    expect(await store.load(), hasLength(251));
  });

  test(
    'concurrent library additions across store instances retain every record',
    () async {
      final records = <PdfRecord>[];
      for (var i = 0; i < 12; i++) {
        final file = await File('${root.path}/$i.pdf').writeAsString('$i');
        records.add(
          PdfRecord(path: file.path, name: '$i.pdf', createdAt: DateTime.now()),
        );
      }
      await Future.wait([
        for (final record in records) PdfFileStore().add(record),
      ]);
      expect(
        (await PdfFileStore().load()).map((r) => r.path).toSet(),
        records.map((r) => r.path).toSet(),
      );
    },
  );

  test('failed queued mutation does not block later mutations', () async {
    final queue = SerialExecutor();
    final failed = expectLater(
      queue.run<void>(() async => throw StateError('failed')),
      throwsStateError,
    );
    final next = queue.run(() async => 42);
    await failed;
    expect(await next, 42);
  });

  test('capture completing after session cleanup is deleted', () async {
    final deleted = Completer<String>();
    final session = ScanTempSession(
      deleteFile: (file) async {
        deleted.complete(file.path);
      },
    );
    await session.cleanupOwned();
    session.own('${root.path}/late.jpg');
    expect(await deleted.future, '${root.path}/late.jpg');
  });

  test('OCR cancellation prevents further progress', () {
    final progress = <int>[];
    final control = PdfOperationControl(
      onProgress: (done, total) => progress.add(done),
    );
    control.progress(0, 5);
    control.cancel();
    expect(() => control.progress(1, 5), throwsA(isA<PdfOperationCancelled>()));
    expect(progress, [0]);
  });
}
