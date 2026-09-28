import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/scan_temp_session.dart';

void main() {
  test('scanner cleanup deletes only files still owned by the scanner',
      () async {
    final deleted = <String>[];
    final session = ScanTempSession(
      deleteFile: (file) async => deleted.add(file.path),
    );

    session.own('/tmp/photo.jpg');
    session.own('/tmp/page-1.jpg');
    session.own('/tmp/page-2.jpg');

    final handedOff = session.handOff([
      '/tmp/page-1.jpg',
      '/tmp/page-2.jpg',
    ]);

    expect(handedOff, ['/tmp/page-1.jpg', '/tmp/page-2.jpg']);

    await session.cleanupOwned();
    expect(deleted, ['/tmp/photo.jpg']);
  });

  test('explicit scanner delete removes ownership and deletes once', () async {
    final deleted = <String>[];
    final session = ScanTempSession(
      deleteFile: (File file) async => deleted.add(file.path),
    );

    session.own('/tmp/page.jpg');
    await session.deletePath('/tmp/page.jpg');
    await session.cleanupOwned();

    expect(deleted, ['/tmp/page.jpg']);
  });

  test('default scanner cleanup deletes a real owned temp file', () async {
    final dir = await Directory.systemTemp.createTemp('pdfmate_scan_secure_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final file = File('${dir.path}/capture.jpg');
    await file.writeAsBytes(List<int>.generate(8192, (i) => i % 251));
    expect(await file.exists(), isTrue);

    final session = ScanTempSession();
    session.own(file.path);
    await session.cleanupOwned();

    expect(await file.exists(), isFalse);
  });
}
