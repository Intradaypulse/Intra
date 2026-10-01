import 'package:document_scan/document_scan.dart';

bool validCropCorners(DocumentCorners corners) {
  final points = [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft];
  double area = 0;
  for (var i = 0; i < 4; i++) {
    final a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4];
    if (!a.x.isFinite || !a.y.isFinite || a.x < 0 || a.x > 1 || a.y < 0 || a.y > 1) return false;
    // Clockwise in screen coordinates; reject crossing, concavity and collapse.
    if ((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) <= 0.0001) return false;
    area += a.x * b.y - b.x * a.y;
  }
  return area / 2 >= 0.005;
}
