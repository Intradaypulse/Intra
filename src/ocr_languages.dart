import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrLanguage {
  const OcrLanguage(this.name, this.script);
  final String name;
  final TextRecognitionScript? script;
}
const ocrLanguages = [
  OcrLanguage('Detect automatically', null),
  OcrLanguage('Hindi', TextRecognitionScript.devanagiri),
  OcrLanguage('Marathi', TextRecognitionScript.devanagiri),
  OcrLanguage('Nepali', TextRecognitionScript.devanagiri),
  OcrLanguage('English', TextRecognitionScript.latin),
  OcrLanguage('French', TextRecognitionScript.latin),
  OcrLanguage('German', TextRecognitionScript.latin),
  OcrLanguage('Spanish', TextRecognitionScript.latin),
  OcrLanguage('Portuguese', TextRecognitionScript.latin),
  OcrLanguage('Italian', TextRecognitionScript.latin),
  OcrLanguage('Dutch', TextRecognitionScript.latin),
  OcrLanguage('Turkish', TextRecognitionScript.latin),
  OcrLanguage('Indonesian', TextRecognitionScript.latin),
  OcrLanguage('Vietnamese', TextRecognitionScript.latin),
  OcrLanguage('Polish', TextRecognitionScript.latin),
  OcrLanguage('Chinese', TextRecognitionScript.chinese),
  OcrLanguage('Japanese', TextRecognitionScript.japanese),
  OcrLanguage('Korean', TextRecognitionScript.korean),
];

/// Score each model's native-script letters, with confidence when available.
/// Latin noise from a failed CJK model must not beat readable native text.
double ocrScriptScore(RecognizedText result, TextRecognitionScript script) {
  var score = 0.0;
  for (final block in result.blocks) {
    for (final line in block.lines) {
      for (final rune in line.text.runes) {
        final fits = switch (script) {
          TextRecognitionScript.devanagiri => rune >= 0x900 && rune <= 0x97F,
          TextRecognitionScript.chinese => rune >= 0x3400 && rune <= 0x9FFF,
          TextRecognitionScript.japanese => rune >= 0x3040 && rune <= 0x30FF,
          TextRecognitionScript.korean => rune >= 0xAC00 && rune <= 0xD7AF || rune >= 0x1100 && rune <= 0x11FF,
          TextRecognitionScript.latin => rune >= 65 && rune <= 90 || rune >= 97 && rune <= 122 || rune >= 0xC0 && rune <= 0x24F,
        };
        if (fits || (script == TextRecognitionScript.latin && rune >= 48 && rune <= 57)) score += (line.confidence ?? .8).clamp(.1, 1);
      }
    }
  }
  return score;
}
