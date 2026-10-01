import 'package:document_scan/document_scan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/crop_geometry.dart';

void main() {
  const valid = DocumentCorners(topLeft: (x: .1, y: .1), topRight: (x: .9, y: .1),
    bottomRight: (x: .9, y: .9), bottomLeft: (x: .1, y: .9));
  test('accepts a convex crop and rejects crossed or collapsed corners', () {
    expect(validCropCorners(valid), isTrue);
    expect(validCropCorners(valid.copyWith(topLeft: valid.bottomRight)), isFalse);
    expect(validCropCorners(valid.copyWith(topRight: valid.bottomLeft, bottomLeft: valid.topRight)), isFalse);
    expect(validCropCorners(valid.copyWith(topLeft: (x: double.nan, y: .1))), isFalse);
  });
}
