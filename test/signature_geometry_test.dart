import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/signature_geometry.dart';

void main() {
  test(
    'large portrait signatures fit the page without changing scale on rotation',
    () {
      double? inkScale;
      for (final degrees in [0.0, 37.0, 90.0, 180.0]) {
        final rect = rotatedSignaturePlacement(
          pageWidth: 300,
          pageHeight: 400,
          x: .95,
          y: .95,
          widthFraction: .95,
          imageWidth: 60,
          imageHeight: 300,
          rotationDegrees: degrees,
        );
        final angle = degrees * math.pi / 180;
        final expanded =
            60 * math.cos(angle).abs() + 300 * math.sin(angle).abs();
        inkScale ??= rect.width / expanded;
        expect(rect.width / expanded, closeTo(inkScale, 1e-8));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(300.000001));
        expect(rect.bottom, lessThanOrEqualTo(400.000001));
      }
    },
  );

  test('free rotation preserves ink scale and centre at every angle', () {
    for (final degrees in [-179.0, -90.0, -37.5, 0.0, 45.0, 90.0, 179.0]) {
      final rect = rotatedSignaturePlacement(
        pageWidth: 600,
        pageHeight: 800,
        x: .5,
        y: .5,
        widthFraction: .3,
        imageWidth: 300,
        imageHeight: 60,
        rotationDegrees: degrees,
      );
      final angle = degrees * math.pi / 180;
      final expandedWidth =
          300 * math.cos(angle).abs() + 60 * math.sin(angle).abs();
      final expandedHeight =
          60 * math.cos(angle).abs() + 300 * math.sin(angle).abs();
      expect(rect.width / expandedWidth, closeTo(.6, 1e-8));
      expect(rect.height / expandedHeight, closeTo(.6, 1e-8));
      expect(rect.center.dx, closeTo(300, 1e-8));
      expect(rect.center.dy, closeTo(400, 1e-8));
      final preview = rotatedSignaturePlacement(
        pageWidth: 300,
        pageHeight: 400,
        x: .5,
        y: .5,
        widthFraction: .3,
        imageWidth: 300,
        imageHeight: 60,
        rotationDegrees: degrees,
      );
      expect(rect.width, closeTo(preview.width * 2, 1e-8));
      expect(rect.height, closeTo(preview.height * 2, 1e-8));
    }
  });

  test('edge placement stays identical at preview and PDF resolutions', () {
    for (final aspect in [3.0, 1.0, 1 / 3]) {
      final preview = signaturePlacement(
        pageWidth: 300,
        pageHeight: 400,
        x: .9,
        y: .95,
        widthFraction: .75,
        imageAspect: aspect,
      );
      final pdf = signaturePlacement(
        pageWidth: 600,
        pageHeight: 800,
        x: .9,
        y: .95,
        widthFraction: .75,
        imageAspect: aspect,
      );
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

// A wide signature previously shrank when rotated into a tall bounding box.
