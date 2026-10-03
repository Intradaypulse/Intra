import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/signature_geometry.dart';

void main() {
  test('edge placement stays identical at preview and PDF resolutions', () {
    for (final aspect in [3.0, 1.0, 1 / 3]) {
      final preview = signaturePlacement(pageWidth: 300, pageHeight: 400,
        x: .9, y: .95, widthFraction: .75, imageAspect: aspect);
      final pdf = signaturePlacement(pageWidth: 600, pageHeight: 800,
        x: .9, y: .95, widthFraction: .75, imageAspect: aspect);
      expect(pdf.left, closeTo(preview.left * 2, .001));
      expect(pdf.top, closeTo(preview.top * 2, .001));
      expect(pdf.width, closeTo(preview.width * 2, .001));
      expect(pdf.height, closeTo(preview.height * 2, .001));
      expect(pdf.right, lessThanOrEqualTo(600));
      expect(pdf.bottom, lessThanOrEqualTo(800));
      expect(pdf.width / pdf.height, closeTo(aspect, .001));
    }
  });
}
