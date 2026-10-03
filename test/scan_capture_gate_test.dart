import 'package:document_scan/document_scan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/scan_capture_gate.dart';
const corners = DocumentCorners(topLeft: (x: .1, y: .1), topRight: (x: .9, y: .1),
  bottomRight: (x: .9, y: .9), bottomLeft: (x: .1, y: .9));
void main() {
  test('requires elapsed hold and fresh frames, then fires once', () {
    final gate = ScanCaptureGate();
    for (var i = 0; i < 14; i++) {
      expect(gate.add(const DetectionSuccess(corners), Duration(milliseconds: i * 100)), isFalse);
    }
    expect(gate.add(const DetectionSuccess(corners), const Duration(milliseconds: 1400)), isTrue);
    expect(gate.add(const DetectionSuccess(corners), const Duration(milliseconds: 1500)), isFalse);
  });
  test('reset after cancel automatically re-arms without moving the document', () {
    final gate = ScanCaptureGate();
    for (var i = 0; i <= 14; i++) { gate.add(const DetectionSuccess(corners), Duration(milliseconds: i * 100)); }
    gate.reset();
    var captures = 0;
    for (var i = 0; i <= 14; i++) {
      if (gate.add(const DetectionSuccess(corners), Duration(milliseconds: 2000 + i * 100))) captures++;
    }
    expect(captures, 1);
  });
  test('missing document and detector gaps restart the hold', () {
    final gate = ScanCaptureGate();
    for (var i = 0; i < 13; i++) { gate.add(const DetectionSuccess(corners), Duration(milliseconds: i * 100)); }
    expect(gate.add(const DetectionSuccess(corners), const Duration(seconds: 8)), isFalse);
    expect(gate.add(const DetectionEmpty(), const Duration(seconds: 9)), isFalse);
    expect(gate.add(const DetectionSuccess(corners), const Duration(seconds: 10)), isFalse);
  });
}
