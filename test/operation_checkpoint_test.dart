import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/pdf_service.dart';

void main() {
  test('dense word loop processes cancellation before another word', () async {
    final control = PdfOperationControl();
    var processed = 0;
    Timer.run(control.cancel);
    Future<void> process() async {
      for (var i = 0; i < 10000; i++) {
        await control.checkpoint();
        processed++;
      }
    }
    await expectLater(process(), throwsA(isA<PdfOperationCancelled>()));
    expect(processed, 0);
  });

  test('already cancelled checkpoint stops immediately', () async {
    final control = PdfOperationControl()..cancel();
    await expectLater(control.checkpoint(), throwsA(isA<PdfOperationCancelled>()));
  });
}
