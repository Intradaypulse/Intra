import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:pdfmate/pdf_service.dart';

// Fixture files and corpus.json live in app-private app_flutter/qa.
// No customer document or recognized text is uploaded by this test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real document OCR corpus', (tester) async {
    final root = '${(await getApplicationDocumentsDirectory()).path}/qa';
    final cases = jsonDecode(await File('$root/corpus.json').readAsString()) as List;
    expect(cases, isNotEmpty, reason: 'A missing corpus must never pass QA.');
    for (final raw in cases) {
      final spec = raw as Map<String, dynamic>;
      final name = spec['file'] as String;
      expect(name, matches(RegExp(r'^[A-Za-z0-9_.-]+\.pdf$')));
      final script = TextRecognitionScript.values.byName(spec['script'] as String);
      final service = PdfService();
      final source = File('$root/$name');
      final count = await service.pageCount(source);
      expect(count, spec['pages']);
      final before = await source.length();
      final timer = Stopwatch()..start();
      final output = await service.makeSearchablePdf(source,
        script: script, tableRows: spec['tableRows'] == true);
      final engine = Pdf();
      PdfDoc? doc;
      try {
        doc = await engine.open(FileSource(output));
        expect(doc.pageCount, count);
        final checks = spec['checks'] as List;
        expect(checks, isNotEmpty);
        for (final rawCheck in checks) {
          final check = rawCheck as Map<String, dynamic>;
          final text = (await doc.extract(pages: PdfPages.single(check['page'] as int)))
              .replaceAll(RegExp(r'\s+'), '');
          final words = (check['orderedText'] as List).cast<String>();
          expect(words, isNotEmpty);
          var cursor = 0;
          for (final word in words) {
            final token = word.replaceAll(RegExp(r'\s+'), '');
            final position = text.indexOf(token, cursor);
            expect(position, greaterThanOrEqualTo(0),
                reason: 'Missing or out-of-order expected token on page ${check['page']}');
            cursor = position + token.length;
          }
        }
        expect(await source.length(), before);
        // Report aggregate measurements, not document contents or file names.
        // ignore: avoid_print
        print('CORPUS_QA pages=$count elapsedMs=${timer.elapsedMilliseconds} '
            'sourceBytes=$before outputBytes=${await output.length()}');
      } finally {
        await doc?.dispose();
        await engine.dispose();
        await output.delete();
      }
    }
  }, timeout: const Timeout(Duration(hours: 2)));
}
