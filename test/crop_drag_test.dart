import 'package:document_scan/document_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/draggable_corner_overlay.dart';

void main() {
  testWidgets('drag preserves grab offset without jumping upward', (tester) async {
    var corners = const DocumentCorners(
      topLeft: (x: .2, y: .2), topRight: (x: .8, y: .2),
      bottomRight: (x: .8, y: .8), bottomLeft: (x: .2, y: .8));
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(
      width: 300, height: 400,
      child: StatefulBuilder(builder: (context, setState) => DraggableCornerOverlay(
        corners: corners,
        onCornerMoved: (index, point) => setState(() {
          expect(index, 0);
          corners = corners.copyWith(topLeft: point);
        }),
      )),
    ))));
    final origin = tester.getTopLeft(find.byType(DraggableCornerOverlay));
    final gesture = await tester.startGesture(origin + const Offset(80, 80));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    final before = corners.topLeft;
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    expect(corners.topLeft.x - before.x, closeTo(10 / 300, .001));
    expect(corners.topLeft.y - before.y, closeTo(10 / 400, .001));
    await gesture.up();
  });
}
