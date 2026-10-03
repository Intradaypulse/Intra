import 'dart:math' as math;
import 'dart:ui';

/// Same top-left rectangle in preview pixels and PDF points. The image is
/// already rotated, so its aspect includes the expanded rotation bounds.
Rect signaturePlacement({
  required double pageWidth,
  required double pageHeight,
  required double x,
  required double y,
  required double widthFraction,
  required double imageAspect,
}) {
  final width = math.min(pageWidth * widthFraction, pageHeight * imageAspect);
  final height = width / imageAspect;
  return Rect.fromLTWH(
    (x * pageWidth).clamp(0.0, math.max(0.0, pageWidth - width)).toDouble(),
    (y * pageHeight).clamp(0.0, math.max(0.0, pageHeight - height)).toDouble(),
    width, height,
  );
}

/// Map a displayed top-left rectangle to unrotated PDF bottom-left coordinates.
Rect signaturePdfRect(Rect view, double width, double height, int rotation) {
  switch (rotation % 360) {
    case 90: return Rect.fromLTWH(view.top, view.left, view.height, view.width);
    case 180: return Rect.fromLTWH(width - view.right, view.top, view.width, view.height);
    case 270: return Rect.fromLTWH(width - view.bottom, height - view.right, view.height, view.width);
    default: return Rect.fromLTWH(view.left, height - view.bottom, view.width, view.height);
  }
}
