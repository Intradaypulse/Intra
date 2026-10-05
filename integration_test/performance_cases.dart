import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfmate/pdf_service.dart';

void registerPerformanceCases() {
  testWidgets('synthetic 300-page index and split stays bounded and preserves page counts', (tester) async {
    final root = await getApplicationDocumentsDirectory();
    final source = File('${root.path}/performance_300.pdf');
    final service = PdfService();
    final parts = <File>[];
    final before = ProcessInfo.currentRss;
    final timer = Stopwatch()..start();
    try {
      final doc = pw.Document();
      for (var page = 0; page < 300; page++) {
        doc.addPage(pw.Page(build: (_) => pw.Text('Benchmark page ${page + 1}')));
      }
      await source.writeAsBytes(await doc.save());
      final bytes = await source.readAsBytes();
      expect((await service.pageInfos(source)).length, 300);
      parts.addAll(await service.splitEveryN(source, 100));
      expect(parts.length, 3);
      for (final part in parts) { expect(await service.pageCount(part), 100); }
      expect(await source.readAsBytes(), bytes);
      final after = ProcessInfo.currentRss;
      expect(after - before, lessThan(512 * 1024 * 1024), reason: 'Unexpected retained memory growth');
      // Synthetic emulator measurements, not a physical-device performance claim.
      // ignore: avoid_print
      print('PERF_QA syntheticPages=300 elapsedMs=${timer.elapsedMilliseconds} rssBefore=$before rssAfter=$after');
    } finally {
      for (final part in parts) { if (await part.exists()) await part.delete(); }
      if (await source.exists()) await source.delete();
    }
  });
  testWidgets('two 12MP camera JPEGs convert without modifying the original files', (tester) async {
    final root = await getApplicationDocumentsDirectory();
    final source = File('${root.path}/performance_12mp.jpg');
    File? output;
    final service = PdfService();
    final timer = Stopwatch()..start();
    final before = ProcessInfo.currentRss;
    try {
      await source.writeAsBytes(img.encodeJpg(img.Image(width: 4000, height: 3000), quality: 95));
      final bytes = await source.readAsBytes();
      output = await service.createScannedPdfFromFiles([source.path, source.path]);
      expect(await service.pageCount(output), 2);
      expect(await source.readAsBytes(), bytes);
      final infos = await service.pageInfos(output);
      expect(infos.first.width / infos.first.height, closeTo(4 / 3, .01));
      final after = ProcessInfo.currentRss;
      expect(after - before, lessThan(512 * 1024 * 1024));
      // ignore: avoid_print
      print('PERF_QA photos=2 pixelsPerPhoto=12000000 elapsedMs=${timer.elapsedMilliseconds} rssBefore=$before rssAfter=$after');
    } finally {
      if (await source.exists()) await source.delete();
      if (output != null && await output.exists()) await output.delete();
    }
  });
}
