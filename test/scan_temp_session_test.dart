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
}
