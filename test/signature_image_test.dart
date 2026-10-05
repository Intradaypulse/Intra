import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfmate/signature_image.dart';

void main() {
  test('legacy padded signature keeps all ink and transparent background', () {
    final legacy = img.Image(width: 900, height: 400, numChannels: 4);
    img.drawLine(legacy, x1: 330, y1: 140, x2: 570, y2: 260,
      color: img.ColorRgba8(0, 0, 0, 255), thickness: 3);
    final originalInk = legacy.where((p) => p.a > 0).length;
    final trimmed = img.decodePng(trimSignaturePng(Uint8List.fromList(img.encodePng(legacy))))!;
    expect(trimmed.width, lessThan(255));
    expect(trimmed.height, lessThan(135));
    expect(trimmed.where((p) => p.a > 0).length, originalInk);
    expect(trimmed.getPixel(0, 0).a, 0);
    expect(trimmed.where((p) => p.a == 255).every((p) => p.r == 0 && p.g == 0 && p.b == 0), isTrue);
    final bytes = Uint8List.fromList(img.encodePng(trimmed));
    expect(trimSignaturePng(bytes), bytes); // no progressive shrink on reuse
  });

  test('empty or corrupt signature cannot silently produce a signed PDF', () {
    final blank = img.Image(width: 80, height: 40, numChannels: 4);
    expect(() => trimSignaturePng(Uint8List.fromList(img.encodePng(blank))), throwsStateError);
    expect(() => trimSignaturePng(Uint8List.fromList([1, 2, 3])), throwsStateError);
  });
}
