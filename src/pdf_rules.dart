import 'dart:math' as math;

class OcrPdfPlacement {
  const OcrPdfPlacement({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

OcrPdfPlacement mapOcrRectToPdf({
  required double leftPx,
  required double topPx,
  required double widthPx,
  required double heightPx,
  required double imageWidthPx,
  required double imageHeightPx,
  required double pdfWidthPt,
  required double pdfHeightPt,
}) {
  if (imageWidthPx <= 0 ||
      imageHeightPx <= 0 ||
      pdfWidthPt <= 0 ||
      pdfHeightPt <= 0) {
    return const OcrPdfPlacement(left: 0, top: 0, width: 0, height: 0);
  }

  final rawLeft = leftPx / imageWidthPx * pdfWidthPt;
  final rawTop = topPx / imageHeightPx * pdfHeightPt;
  final rawWidth = widthPx / imageWidthPx * pdfWidthPt;
  final rawHeight = heightPx / imageHeightPx * pdfHeightPt;

  final left = rawLeft.clamp(0.0, pdfWidthPt).toDouble();
  final top = rawTop.clamp(0.0, pdfHeightPt).toDouble();
  final width = math
      .min(math.max(0.0, rawWidth), math.max(0.0, pdfWidthPt - left))
      .toDouble();
  final height = math
      .min(math.max(0.0, rawHeight), math.max(0.0, pdfHeightPt - top))
      .toDouble();

  return OcrPdfPlacement(
    left: left,
    top: top,
    width: width,
    height: height,
  );
}

int splitChunkCount(int pageCount, int every) {
  if (pageCount < 0) {
    throw ArgumentError.value(pageCount, 'pageCount');
  }
  if (every < 1) {
    throw ArgumentError.value(every, 'every');
  }
  if (pageCount == 0) return 0;
  return (pageCount / every).ceil();
}

bool needsRewardedOcrGate({
  required int pageCount,
  required int threshold,
  required bool alreadyUnlocked,
}) {
  if (threshold < 1) {
    throw ArgumentError.value(threshold, 'threshold');
  }
  return !alreadyUnlocked && pageCount > threshold;
}

bool isPdfMateManagedTempPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last;
  return name.startsWith('pdfmate_secure_tmp_');
}

// Unicode overlay regression trigger.
