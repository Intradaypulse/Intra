import 'dart:math' as math;

/// Geometry is in the upright rendered page's coordinates, before /Rotate.
class OcrRegion<T> {
  const OcrRegion(this.value, this.left, this.top, this.right, this.bottom);
  final T value;
  final double left, top, right, bottom;
}

/// Recursive whitespace cuts keep separated columns together and spanning
/// headings ahead of columns. RTL changes column traversal, never characters.
List<T> ocrReadingOrder<T>(List<OcrRegion<T>> regions, {bool rtl = false}) {
  if (regions.length < 2) return regions.map((r) => r.value).toList();
  for (final vertical in [true, false]) {
    final sorted = [...regions]
      ..sort(
        (a, b) =>
            (vertical ? a.left : a.top).compareTo(vertical ? b.left : b.top),
      );
    var edge = vertical ? sorted.first.right : sorted.first.bottom;
    var split = -1;
    var gap = 0.0;
    for (var i = 1; i < sorted.length; i++) {
      final start = vertical ? sorted[i].left : sorted[i].top;
      if (start - edge > gap) {
        gap = start - edge;
        split = i;
      }
      edge = math.max(edge, vertical ? sorted[i].right : sorted[i].bottom);
    }
    if (split > 0 && gap > .5) {
      final first = ocrReadingOrder(sorted.sublist(0, split), rtl: rtl);
      final second = ocrReadingOrder(sorted.sublist(split), rtl: rtl);
      return vertical && rtl ? [...second, ...first] : [...first, ...second];
    }
  }
  final sorted = [...regions]
    ..sort((a, b) {
      final row = a.top.compareTo(b.top);
      return row != 0
          ? row
          : (rtl ? b.left.compareTo(a.left) : a.left.compareTo(b.left));
    });
  return sorted.map((r) => r.value).toList();
}

Map<String, Object> ocrWordGeometry({
  required String text,
  required List<math.Point<int>> corners,
  required double left,
  required double top,
  required double width,
  required double height,
  required double scaleX,
  required double scaleY,
  double angle = 0,
}) {
  // Corner points describe skew/rotation more accurately than an axis-aligned
  // rectangle. Keep an explicit baseline origin for the native PDF text matrix.
  var x = left * scaleX, y = top * scaleY;
  var w = width * scaleX, h = height * scaleY;
  if (corners.length == 4) {
    final tl = corners[0], tr = corners[1], bl = corners[3];
    final dx = (tr.x - tl.x) * scaleX, dy = (tr.y - tl.y) * scaleY;
    final hx = (bl.x - tl.x) * scaleX, hy = (bl.y - tl.y) * scaleY;
    w = math.sqrt(dx * dx + dy * dy);
    h = math.sqrt(hx * hx + hy * hy);
    x = tl.x * scaleX + hx * .85;
    y = tl.y * scaleY + hy * .85;
    angle = math.atan2(dy, dx) * 180 / math.pi;
  } else {
    y += h * .85;
  }
  return {
    'text': text,
    'x': x,
    'y': y,
    'width': w,
    'height': h,
    'angle': angle,
  };
}
