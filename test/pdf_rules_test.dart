import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/pdf_rules.dart';

void main() {
  group('OCR positioning', () {
    test('maps image coordinates to PDF points', () {
      final p = mapOcrRectToPdf(
        leftPx: 100,
        topPx: 200,
        widthPx: 400,
        heightPx: 100,
        imageWidthPx: 1000,
        imageHeightPx: 2000,
        pdfWidthPt: 600,
        pdfHeightPt: 800,
      );

      expect(p.left, closeTo(60, 0.001));
      expect(p.top, closeTo(80, 0.001));
      expect(p.width, closeTo(240, 0.001));
      expect(p.height, closeTo(40, 0.001));
    });

    test('clamps OCR rectangles to page bounds', () {
      final p = mapOcrRectToPdf(
        leftPx: 900,
        topPx: 1900,
        widthPx: 300,
        heightPx: 300,
        imageWidthPx: 1000,
        imageHeightPx: 2000,
        pdfWidthPt: 600,
        pdfHeightPt: 800,
      );

      expect(p.left, closeTo(540, 0.001));
      expect(p.top, closeTo(760, 0.001));
      expect(p.width, closeTo(60, 0.001));
      expect(p.height, closeTo(40, 0.001));
    });
  });

  group('split rules', () {
    test('calculates chunks without dropping trailing pages', () {
      expect(splitChunkCount(10, 3), 4);
      expect(splitChunkCount(3, 3), 1);
      expect(splitChunkCount(0, 3), 0);
    });

    test('rejects invalid split size', () {
      expect(() => splitChunkCount(10, 0), throwsArgumentError);
    });
  });

  group('rewarded OCR rules', () {
    test('gates only documents above the configured threshold', () {
      expect(
        needsRewardedOcrGate(
          pageCount: 10,
          threshold: 10,
          alreadyUnlocked: false,
        ),
        isFalse,
      );
      expect(
        needsRewardedOcrGate(
          pageCount: 11,
          threshold: 10,
          alreadyUnlocked: false,
        ),
        isTrue,
      );
      expect(
        needsRewardedOcrGate(
          pageCount: 50,
          threshold: 10,
          alreadyUnlocked: true,
        ),
        isFalse,
      );
    });
  });

  group('managed temporary file rules', () {
    test('matches only PDFMate secure temporary names', () {
      expect(
        isPdfMateManagedTempPath('/tmp/pdfmate_secure_tmp_decrypted_123.pdf'),
        isTrue,
      );
      expect(
        isPdfMateManagedTempPath(r'C:\Temp\pdfmate_secure_tmp_ocr_2.png'),
        isTrue,
      );
      expect(isPdfMateManagedTempPath('/tmp/customer.pdf'), isFalse);
    });
  });
}
