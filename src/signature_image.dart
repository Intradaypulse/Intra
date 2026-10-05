import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:signature/signature.dart';

/// Export at the drawing's own bounds. Fixed canvas dimensions add transparent
/// padding rather than scaling the ink, making it disappear at PDF page scale.
Future<Uint8List> exportSignaturePng(SignatureController controller) async {
  final image = await controller.toImage();
  if (image == null) throw StateError('Draw a signature first.');
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not export signature.');
    return trimSignaturePng(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  } finally {
    image.dispose();
  }
}

/// Also repairs transparent padding in signatures saved by older app versions.
/// Keep every nonzero alpha pixel and a small margin; never flatten onto white.
Uint8List trimSignaturePng(Uint8List bytes) {
  final image = img.decodePng(bytes);
  if (image == null) throw StateError('Invalid signature image.');
  var left = image.width, top = image.height, right = -1, bottom = -1;
  for (final pixel in image) {
    if (pixel.a == 0) continue;
    if (pixel.x < left) left = pixel.x;
    if (pixel.y < top) top = pixel.y;
    if (pixel.x > right) right = pixel.x;
    if (pixel.y > bottom) bottom = pixel.y;
  }
  if (right < left) throw StateError('Signature has no visible ink. Please draw it again.');
  const margin = 3;
  left = (left - margin).clamp(0, image.width - 1);
  top = (top - margin).clamp(0, image.height - 1);
  right = (right + margin).clamp(0, image.width - 1);
  bottom = (bottom + margin).clamp(0, image.height - 1);
  if (left == 0 && top == 0 && right == image.width - 1 && bottom == image.height - 1) return bytes;
  return Uint8List.fromList(img.encodePng(img.copyCrop(image,
    x: left, y: top, width: right - left + 1, height: bottom - top + 1)));
}
