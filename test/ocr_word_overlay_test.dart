import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:pdfmate/ocr_page_preview_screen.dart';
import 'package:pdfmate/pdf_service.dart';

class _MixedPreviewService extends PdfService {
  @override
  Future<OcrPagePreview> recognizePage(
    File source,
    int pageIndex, {
    TextRecognitionScript? script,
    String? password,
    PdfOperationControl? control,
  }) async => OcrPagePreview(
    bytes: Uint8List.fromList(
      img.encodePng(img.Image(width: 200, height: 200)),
    ),
    width: 200,
    height: 200,
    script: TextRecognitionScript.devanagiri,
    text: RecognizedText(
      text: 'Hello नमस्ते',
      blocks: [
        TextBlock(
          text: 'Hello नमस्ते',
          boundingBox: const Rect.fromLTWH(10, 20, 170, 24),
          recognizedLanguages: ['en', 'hi'],
          cornerPoints: [],
          lines: [
            TextLine(
              text: 'Hello नमस्ते',
              boundingBox: const Rect.fromLTWH(10, 20, 170, 24),
              recognizedLanguages: ['en', 'hi'],
              cornerPoints: [],
              confidence: .9,
              angle: 0,
              elements: [
                TextElement(
                  text: 'Hello',
                  symbols: [],
                  boundingBox: const Rect.fromLTWH(10, 20, 70, 24),
                  recognizedLanguages: ['en'],
                  cornerPoints: [],
                  confidence: .9,
                  angle: 0,
                ),
                TextElement(
                  text: 'नमस्ते',
                  symbols: [],
                  boundingBox: const Rect.fromLTWH(100, 20, 80, 24),
                  recognizedLanguages: ['hi'],
                  cornerPoints: [],
                  confidence: .9,
                  angle: 0,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

void main() {
  testWidgets(
    'paragraph selection and handles preserve Unicode and image coordinates',
    (tester) async {
      final semantics = tester.ensureSemantics();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: OcrPagePreviewScreen(
              service: _MixedPreviewService(),
              source: File('/tmp/page.pdf'),
              pageCount: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('नमस्ते'));
        await tester.pump();
        await tester.tap(find.bySemanticsLabel('Hello'));
        await tester.pump();
        await tester.tap(find.text('Copy selected'));
        await tester.pumpAndSettle();
        expect(copied, 'Hello नमस्ते');
        await tester.longPress(find.bySemanticsLabel('नमस्ते'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy selected'));
        await tester.pumpAndSettle();
        expect(copied, 'Hello नमस्ते');
        final handle = find.bySemanticsLabel('Selection start');
        final word = tester.getCenter(find.bySemanticsLabel('नमस्ते'));
        await tester.drag(handle, word - tester.getCenter(handle));
        await tester.pump();
        await tester.tap(find.text('Copy selected'));
        await tester.pumpAndSettle();
        expect(copied, 'नमस्ते');
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(find.text('Hello'), findsNothing);
        await tester.longPress(find.bySemanticsLabel('Hello'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy selected'));
        await tester.pumpAndSettle();
        expect(copied, 'Hello नमस्ते');
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      }
    },
  );
}
