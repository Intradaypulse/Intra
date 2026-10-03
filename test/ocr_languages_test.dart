import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfmate/ocr_languages.dart';
RecognizedText sample(String value) => RecognizedText(text: value, blocks: [TextBlock(
  text: value, boundingBox: const Rect.fromLTWH(0, 0, 100, 20), recognizedLanguages: [], cornerPoints: [],
  lines: [TextLine(text: value, elements: [], boundingBox: const Rect.fromLTWH(0, 0, 100, 20),
    recognizedLanguages: [], cornerPoints: [], confidence: null, angle: null)])]);
void main() {
  test('native letters outrank Latin noise for Devanagari detection', () {
    final text = sample('हिन्दी भाषा नमस्ते English');
    expect(ocrScriptScore(text, TextRecognitionScript.devanagiri),
      greaterThan(ocrScriptScore(text, TextRecognitionScript.latin)));
    expect(ocrScriptScore(text, TextRecognitionScript.korean), 0);
  });
  test('Japanese kana and Korean Hangul are distinguished from Han', () {
    expect(ocrScriptScore(sample('こんにちは'), TextRecognitionScript.japanese), greaterThan(0));
    expect(ocrScriptScore(sample('こんにちは'), TextRecognitionScript.chinese), 0);
    expect(ocrScriptScore(sample('안녕하세요'), TextRecognitionScript.korean), greaterThan(0));
  });
}
