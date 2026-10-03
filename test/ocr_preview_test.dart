import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:pdfmate/ocr_page_preview_screen.dart';
import 'package:pdfmate/pdf_service.dart';
class PreviewService extends PdfService {
  @override Future<OcrPagePreview> recognizePage(File source, int pageIndex, {
    TextRecognitionScript? script, String? password, PdfOperationControl? control,
  }) async => OcrPagePreview(bytes: Uint8List.fromList(img.encodePng(img.Image(width: 100, height: 200))),
    width: 100, height: 200, script: TextRecognitionScript.latin,
    text: RecognizedText(text: 'Hello preview', blocks: [TextBlock(text: 'Hello preview',
      boundingBox: const Rect.fromLTWH(10, 10, 80, 20), recognizedLanguages: ['en'], cornerPoints: [],
      lines: [TextLine(text: 'Hello preview', elements: [], boundingBox: const Rect.fromLTWH(10, 10, 80, 20),
        recognizedLanguages: ['en'], cornerPoints: [], confidence: .9, angle: 0)])]));
}
void main() {
  testWidgets('copies text selected directly on the page image', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.pumpWidget(MaterialApp(home: OcrPagePreviewScreen(
      service: PreviewService(), source: File('/tmp/page.pdf'), pageCount: 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Hello preview'));
    await tester.pump();
    await tester.tap(find.text('Copy selected'));
    await tester.pumpAndSettle();
    expect(copied, 'Hello preview');
  });
}
