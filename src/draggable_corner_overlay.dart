import 'package:document_scan/document_scan.dart';
import 'package:flutter/material.dart';

class DraggableCornerOverlay extends StatefulWidget {
  const DraggableCornerOverlay({
    super.key,
    required this.corners,
    required this.onCornerMoved,
  });

  final DocumentCorners corners;
  final void Function(int index, ({double x, double y}) point) onCornerMoved;

  @override
  State<DraggableCornerOverlay> createState() => _DraggableCornerOverlayState();
}

class _DraggableCornerOverlayState extends State<DraggableCornerOverlay> {
  static const _stroke = Color(0xFF4F7CFF);
  static const _fill = Color(0x224F7CFF);
  static const _handle = Color(0xFF4F7CFF);
  static const double _hitRadius = 48;
  Offset _dragOffset = Offset.zero;

  int? _activeHandle;
  Size _size = Size.zero;

  List<({double x, double y})> get _points => [
        widget.corners.topLeft,
        widget.corners.topRight,
        widget.corners.bottomRight,
        widget.corners.bottomLeft,
      ];

  Offset _toLocal(({double x, double y}) p) =>
      Offset(p.x * _size.width, p.y * _size.height);

  void _onPanStart(DragStartDetails details) {
    var nearest = -1;
    var nearestDistance = _hitRadius;
    final points = _points;
    for (var i = 0; i < points.length; i++) {
      final d = (details.localPosition - _toLocal(points[i])).distance;
      if (d < nearestDistance) {
        nearest = i;
        nearestDistance = d;
      }
    }
    if (nearest >= 0) {
      _dragOffset = _toLocal(points[nearest]) - details.localPosition;
    }
    setState(() => _activeHandle = nearest >= 0 ? nearest : null);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final active = _activeHandle;
    if (active == null || _size.isEmpty) return;
    final lifted = details.localPosition + _dragOffset;
    widget.onCornerMoved(active, (
      x: (lifted.dx / _size.width).clamp(0.0, 1.0),
      y: (lifted.dy / _size.height).clamp(0.0, 1.0),
    ));
  }

  void _onPanEnd(DragEndDetails _) => setState(() => _activeHandle = null);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onPanCancel: () => setState(() => _activeHandle = null),
          child: CustomPaint(
            painter: _CornerPainter(
              corners: widget.corners,
              active: _activeHandle,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({required this.corners, required this.active});

  final DocumentCorners corners;
  final int? active;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(({double x, double y}) p) =>
        Offset(p.x * size.width, p.y * size.height);

    final points = [
      at(corners.topLeft),
      at(corners.topRight),
      at(corners.bottomRight),
      at(corners.bottomLeft),
    ];

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = _DraggableCornerOverlayState._fill
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _DraggableCornerOverlayState._stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final selected = i == active;
      if (selected) {
        canvas.drawCircle(
          p,
          30,
          Paint()
            ..color = _DraggableCornerOverlayState._handle
                .withValues(alpha: 0.16),
        );
      }
      canvas.drawCircle(p, selected ? 18 : 15, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        selected ? 14 : 11,
        Paint()..color = _DraggableCornerOverlayState._handle,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) =>
      oldDelegate.corners != corners || oldDelegate.active != active;
}
