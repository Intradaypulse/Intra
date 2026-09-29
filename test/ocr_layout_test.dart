import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/ocr_layout.dart';

void main() {
  test('spanning header precedes columns; columns remain contiguous', () {
    final regions = [
      const OcrRegion('R2', 200, 100, 300, 120),
      const OcrRegion('L2', 0, 100, 100, 120),
      const OcrRegion('heading', 0, 0, 300, 20),
      const OcrRegion('R1', 200, 50, 300, 70),
      const OcrRegion('L1', 0, 50, 100, 70),
    ];
    expect(ocrReadingOrder(regions), ['heading', 'L1', 'L2', 'R1', 'R2']);
    expect(ocrReadingOrder(regions, rtl: true), [
      'heading',
      'R1',
      'R2',
      'L1',
      'L2',
    ]);
  });
  test('table mode reads across rows; RTL reverses cells only', () {
    final cells = [
      const OcrRegion('A1', 0, 0, 40, 15),
      const OcrRegion('B1', 100, 0, 140, 15),
      const OcrRegion('A2', 0, 30, 40, 45),
      const OcrRegion('B2', 100, 30, 140, 45),
    ];
    expect(ocrReadingOrder(cells, tableRows: true), ['A1', 'B1', 'A2', 'B2']);
    expect(ocrReadingOrder(cells, tableRows: true, rtl: true), [
      'B1',
      'A1',
      'B2',
      'A2',
    ]);
  });
  test('horizontal rows and empty input have stable order', () {
    expect(ocrReadingOrder<String>([]), isEmpty);
    expect(
      ocrReadingOrder([
        const OcrRegion('bottom', 0, 50, 300, 70),
        const OcrRegion('top', 0, 0, 300, 20),
      ]),
      ['top', 'bottom'],
    );
  });
  test('rotated word uses quadrilateral baseline and scaled edge lengths', () {
    final g = ocrWordGeometry(
      text: 'Hindi',
      corners: [
        const Point(100, 20),
        const Point(100, 120),
        const Point(80, 120),
        const Point(80, 20),
      ],
      left: 80,
      top: 20,
      width: 20,
      height: 100,
      scaleX: .5,
      scaleY: .5,
    );
    expect(g['angle'], closeTo(90, .001));
    expect(g['width'], closeTo(50, .001));
    expect(g['height'], closeTo(10, .001));
    expect(g['x'], closeTo(41.5, .001));
    expect(g['y'], closeTo(10, .001));
  });
  test('missing corners use explicit rectangle baseline', () {
    final g = ocrWordGeometry(
      text: 'word',
      corners: [],
      left: 20,
      top: 30,
      width: 100,
      height: 20,
      scaleX: .5,
      scaleY: .5,
      angle: 5,
    );
    expect(g['x'], 10);
    expect(g['y'], 23.5);
    expect(g['angle'], 5);
  });
}
