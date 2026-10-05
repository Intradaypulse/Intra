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
    width,
    height,
  );
}

/// Map a displayed top-left rectangle to unrotated PDF bottom-left coordinates.
Rect signaturePdfRect(Rect view, double width, double height, int rotation) {
  switch (((rotation % 360) + 360) % 360) {
    case 90:
      return Rect.fromLTWH(view.top, view.left, view.height, view.width);
    case 180:
      return Rect.fromLTWH(
        width - view.right,
        view.top,
        view.width,
        view.height,
      );
    case 270:
      return Rect.fromLTWH(
        width - view.bottom,
        height - view.right,
        view.height,
        view.width,
      );
    default:
      return Rect.fromLTWH(
        view.left,
        height - view.bottom,
        view.width,
        view.height,
      );
  }
}

/// pdf_manipulator 5.0.1 searches spans in its displayed MediaBox frame.
/// On 90/270 pages it leaves raw horizontal runs unrotated; 180 maps all runs.
/// The OCR angle identifies horizontal source content after page rotation.
Offset ocrSearchPoint(
  Offset point,
  Rect media,
  int rotation,
  double wordAngle,
) {
  final rot = ((rotation % 360) + 360) % 360;
  final contentAngle = ((rot - wordAngle + 180) % 360) - 180;
  if (rot == 0 || (rot != 180 && contentAngle.abs() < 2)) return point;
  final x = point.dx - media.left, y = point.dy - media.top;
  final mapped = switch (rot) {
    90 => Offset(y, media.width - x),
    180 => Offset(media.width - x, media.height - y),
    270 => Offset(media.height - y, x),
    _ => Offset(x, y),
  };
  return mapped + media.topLeft;
}

/// Rotation changes the bounding box, never the ink's pixels-per-point scale.
/// x/y identify its centre so rotating does not move the signature's anchor.
Rect rotatedSignaturePlacement({
  required double pageWidth,
  required double pageHeight,
  required double x,
  required double y,
  required double widthFraction,
  required double imageWidth,
  required double imageHeight,
  required double rotationDegrees,
}) {
  // A rotation-independent upper bound keeps every orientation on the page.
  final diagonal = math.sqrt(
    imageWidth * imageWidth + imageHeight * imageHeight,
  );
  final scale = math.min(
    pageWidth * widthFraction / imageWidth,
    math.min(pageWidth, pageHeight) / diagonal,
  );
  final angle = rotationDegrees * math.pi / 180;
  final width =
      (imageWidth * math.cos(angle).abs() +
          imageHeight * math.sin(angle).abs()) *
      scale;
  final height =
      (imageHeight * math.cos(angle).abs() +
          imageWidth * math.sin(angle).abs()) *
      scale;
  return Rect.fromLTWH(
    (x * pageWidth - width / 2)
        .clamp(0.0, math.max(0.0, pageWidth - width))
        .toDouble(),
    (y * pageHeight - height / 2)
        .clamp(0.0, math.max(0.0, pageHeight - height))
        .toDouble(),
    width,
    height,
  );
}
