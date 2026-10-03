import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/signature_store.dart';
void main() {
  test('saved signatures survive reload; malformed and interrupted writes do not block', () async {
    final root = await Directory.systemTemp.createTemp('signature_store_');
    try {
      final store = SignatureStore(directoryProvider: () async => root);
      await store.save('राज / Owner', Uint8List.fromList([137, 80, 78, 71]));
      final dir = Directory('${root.path}/saved_signatures');
      await File('${dir.path}/bad.invalid.png').writeAsString('bad');
      final pending = File('${dir.path}/interrupted.png.pending');
      await pending.writeAsString('partial');
      final loaded = await SignatureStore(directoryProvider: () async => root).load();
      expect(loaded.map((s) => s.name), ['राज / Owner']);
      expect(await pending.exists(), isFalse);
      await store.delete(loaded.single);
      expect(await store.load(), isEmpty);
    } finally { await root.delete(recursive: true); }
  });
}
