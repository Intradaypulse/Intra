import 'dart:io';
import 'dart:typed_data';

import 'package:document_scan/document_scan.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';

enum CompressionPreset { highQuality, balanced, smallest }

class CompressionResult {
  const CompressionResult({
    required this.file,
    required this.originalBytes,
    required this.outputBytes,
  });

  final File file;
  final int originalBytes;
  final int outputBytes;

  int get savedBytes => originalBytes - outputBytes;

  double get savedPercent => originalBytes <= 0
      ? 0
      : ((originalBytes - outputBytes) / originalBytes * 100)
          .clamp(-999, 100)
          .toDouble();
}

class PdfService {
  PdfService();

  final ImagePicker imagePicker = ImagePicker();

  Future<Directory> _docs() => getApplicationDocumentsDirectory();

  String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  Future<File> _newFile(String prefix) async {
    final dir = await _docs();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return File('${dir.path}/${_safe(prefix)}_$stamp.pdf');
  }



  Future<Uri?> exportPdf(File source, String fileName) async {
    return FilePicker.saveFile(
      fileName: fileName,
      bytes: await source.readAsBytes(),
      mimeType: 'application/pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      dialogTitle: 'Save PDF',
    );
  }

  Future<Uint8List?> captureScannedPage({
    String filter = 'enhance',
  }) async {
    final shot = await imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (shot == null) return null;
    final scanFilter = switch (filter) {
      'blackWhite' => ScanFilter.blackWhite,
      'magicColor' => ScanFilter.magicColor,
      'grayscale' => ScanFilter.grayscale,
      'none' => ScanFilter.none,
      _ => ScanFilter.enhance,
    };
    final scanner = DocumentScanner();
    final scanned = await scanner.scan(
      ScanInput.file(shot.path),
      filter: scanFilter,
      output: ScanOutputFormat.png,
    );
    return scanned?.bytes ?? await shot.readAsBytes();
  }

  Future<File> createScannedPdf(List<Uint8List> pages) =>
      _imagesToPdfBytes(pages, 'Scan');

  Future<File?> scanDocument() async {
    final shot = await imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (shot == null) return null;

    final scanner = DocumentScanner();
    final scanned = await scanner.scan(ScanInput.file(shot.path));
    final bytes = scanned?.bytes ?? await shot.readAsBytes();
    return _imagesToPdfBytes([bytes], 'Scan');
  }

  Future<File?> imagesToPdf() async {
    final images = await imagePicker.pickMultiImage(imageQuality: 92);
    if (images.isEmpty) return null;
    final bytes = <Uint8List>[];
    for (final image in images) {
      bytes.add(await image.readAsBytes());
    }
    return _imagesToPdfBytes(bytes, 'Images');
  }

  Future<File> _imagesToPdfBytes(
    List<Uint8List> images,
    String prefix,
  ) async {
    final document = pw.Document();
    for (final bytes in images) {
      final image = pw.MemoryImage(bytes);
      document.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(14),
          build: (_) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }
    final file = await _newFile(prefix);
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }

  Future<PlatformFile?> pickPdf() => FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );

  Future<List<PlatformFile>> pickPdfs() => FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );

  Future<File> _materialize(PlatformFile picked) async {
    final path = picked.path;
    if (path != null && await File(path).exists()) return File(path);
    final tmp = await getTemporaryDirectory();
    final file = File(
      '${tmp.path}/${DateTime.now().microsecondsSinceEpoch}_${_safe(picked.name)}',
    );
    await file.writeAsBytes(await picked.readAsBytes(), flush: true);
    return file;
  }

  Future<File?> compressPdf() async {
    final picked = await pickPdf();
    if (picked == null) return null;
    final sourceFile = await _materialize(picked);
    final outputFile = await _newFile('Compressed');
    final pdf = Pdf();
    final sink = await FileSink.create(outputFile);
    try {
      await pdf.compress(
        FileSource(sourceFile),
        sink,
        images: PdfImagePolicy.ebook,
      );
      await sink.close();
      return outputFile;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<File?> mergePdfs() async {
    final picked = await pickPdfs();
    if (picked.length < 2) return null;
    final inputs = <File>[];
    for (final item in picked) {
      inputs.add(await _materialize(item));
    }

    final outputFile = await _newFile('Merged');
    final pdf = Pdf();
    final sink = await FileSink.create(outputFile);
    try {
      await pdf.merge(
        inputs.map((e) => FileSource(e) as DataSource).toList(),
        sink,
      );
      await sink.close();
      return outputFile;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<List<File>> splitEveryPage() async {
    final picked = await pickPdf();
    if (picked == null) return const [];
    final sourceFile = await _materialize(picked);
    final pdf = Pdf();
    final sinks = <MemorySink>[];
    try {
      await pdf.split(
        FileSource(sourceFile),
        (index) {
          final sink = MemorySink();
          sinks.add(sink);
          return sink;
        },
        every: 1,
      );
      final outputs = <File>[];
      for (var i = 0; i < sinks.length; i++) {
        final file = await _newFile('Split_${i + 1}');
        await file.writeAsBytes(sinks[i].takeBytes(), flush: true);
        outputs.add(file);
      }
      return outputs;
    } finally {
      await pdf.dispose();
    }
  }

  Future<File?> rotateAllPages() async {
    final picked = await pickPdf();
    if (picked == null) return null;
    final sourceFile = await _materialize(picked);
    final outputFile = await _newFile('Rotated');
    final pdf = Pdf();
    final sink = await FileSink.create(outputFile);
    try {
      await pdf.rotateAllPages(
        FileSource(sourceFile),
        sink,
        degrees: 90,
      );
      await sink.close();
      return outputFile;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<File?> passwordProtect(String password) async {
    final picked = await pickPdf();
    if (picked == null) return null;
    final sourceFile = await _materialize(picked);
    final outputFile = await _newFile('Protected');
    final pdf = Pdf();
    final sink = await FileSink.create(outputFile);
    try {
      await pdf.encrypt(
        FileSource(sourceFile),
        sink,
        encryption: PdfEncryptionConfig(
          ownerPassword: password,
          userPassword: password,
          algorithm: PdfEncryptionAlgorithm.aes256,
        ),
      );
      await sink.close();
      return outputFile;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<String?> ocrImage() async {
    final image = await imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      return result.text;
    } finally {
      await recognizer.close();
    }
  }

  Future<int?> selectedPdfPageCount() async {
    final picked = await pickPdf();
    if (picked == null) return null;
    final sourceFile = await _materialize(picked);
    final pdf = Pdf();
    PdfDoc? doc;
    try {
      doc = await pdf.open(FileSource(sourceFile));
      return doc.pageCount;
    } finally {
      await doc?.dispose();
      await pdf.dispose();
    }
  }

  Future<File?> deletePdfPages(List<int> zeroBasedPages) async {
    final picked = await pickPdf();
    if (picked == null || zeroBasedPages.isEmpty) return null;
    final sourceFile = await _materialize(picked);
    final outputFile = await _newFile('Pages_Deleted');
    final pdf = Pdf();
    final sink = await FileSink.create(outputFile);
    try {
      await pdf.deletePages(
        FileSource(sourceFile),
        sink,
        pages: zeroBasedPages,
      );
      await sink.close();
      return outputFile;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<File?> reorderPdfPages(List<int> zeroBasedOrder) async {
    final picked = await pickPdf();
    if (picked == null || zeroBasedOrder.isEmpty) return null;
    final sourceFile = await _materialize(picked);
    final outputFile = await _newFile('Reordered');
    final pdf = Pdf();
    final sink = await FileSink.create(outputFile);
    try {
      await pdf.reorderPages(
        FileSource(sourceFile),
        sink,
        order: zeroBasedOrder,
      );
      await sink.close();
      return outputFile;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<List<File>> pdfToJpg() async {
    final picked = await pickPdf();
    if (picked == null) return const [];
    final sourceFile = await _materialize(picked);
    final pdf = Pdf();
    PdfDoc? doc;
    final outputs = <File>[];
    try {
      doc = await pdf.open(FileSource(sourceFile));
      var pageNo = 1;
      await for (final page in doc.render(
        pages: const PdfPages.all(),
        size: const PdfRenderSize(maxWidth: 2000, maxHeight: 2800),
      )) {
        final decoded = img.decodePng(page.data);
        if (decoded == null) continue;
        final jpgBytes = img.encodeJpg(decoded, quality: 88);
        final dir = await _docs();
        final path =
            '${dir.path}/PDF_Page_${pageNo}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(path);
        await file.writeAsBytes(jpgBytes, flush: true);
        outputs.add(file);
        pageNo++;
      }
      return outputs;
    } finally {
      await doc?.dispose();
      await pdf.dispose();
    }
  }

  Future<String?> extractPdfText() async {
    final picked = await pickPdf();
    if (picked == null) return null;
    final sourceFile = await _materialize(picked);
    final pdf = Pdf();
    PdfDoc? doc;
    try {
      doc = await pdf.open(FileSource(sourceFile));
      return await doc.extract(pages: const PdfPages.all());
    } finally {
      await doc?.dispose();
      await pdf.dispose();
    }
  }

  Future<File?> addSignature(Uint8List signaturePng) async {
    final picked = await pickPdf();
    if (picked == null) return null;
    final sourceFile = await _materialize(picked);
    final outputFile = await _newFile('Signed');
    final pdf = Pdf();
    final sink = await FileSink.create(outputFile);
    try {
      await pdf.addImageStamp(
        FileSource(sourceFile),
        sink,
        page: 0,
        imageData: MemorySource(signaturePng),
        rect: const PdfRect(x: 72, y: 72, width: 180, height: 80),
        opacity: 1,
      );
      await sink.close();
      return outputFile;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }


  Future<File?> pickPdfFile() async {
    final picked = await pickPdf();
    if (picked == null) return null;
    return _materialize(picked);
  }

  Future<List<File>> pickPdfFiles() async {
    final picked = await pickPdfs();
    final files = <File>[];
    for (final item in picked) {
      files.add(await _materialize(item));
    }
    return files;
  }

  Future<int> pageCount(File source, {String? password}) async {
    final pdf = Pdf();
    PdfDoc? doc;
    try {
      doc = await pdf.open(FileSource(source), password: password);
      return doc.pageCount;
    } finally {
      await doc?.dispose();
      await pdf.dispose();
    }
  }

  Future<List<Uint8List>> renderThumbnails(
    File source, {
    String? password,
    int width = 240,
  }) async {
    final pdf = Pdf();
    PdfDoc? doc;
    final result = <Uint8List>[];
    try {
      doc = await pdf.open(FileSource(source), password: password);
      await for (final page in doc.render(
        pages: const PdfPages.all(),
        size: PdfRenderSize.thumbnail(width),
      )) {
        result.add(page.data);
      }
      return result;
    } finally {
      await doc?.dispose();
      await pdf.dispose();
    }
  }

  Future<CompressionResult> compressAdvanced(
    File source,
    CompressionPreset preset,
  ) async {
    final output = await _newFile('Compressed');
    final pdf = Pdf();
    final sink = await FileSink.create(output);
    final originalBytes = await source.length();
    try {
      final policy = switch (preset) {
        CompressionPreset.highQuality => PdfImagePolicy.print,
        CompressionPreset.balanced => PdfImagePolicy.ebook,
        CompressionPreset.smallest => PdfImagePolicy.screen,
      };
      await pdf.compress(
        FileSource(source),
        sink,
        images: policy,
      );
      await sink.close();
      return CompressionResult(
        file: output,
        originalBytes: originalBytes,
        outputBytes: await output.length(),
      );
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<File> mergeFiles(List<File> inputs) async {
    if (inputs.length < 2) {
      throw ArgumentError('Select at least two PDF files.');
    }
    final output = await _newFile('Merged');
    final pdf = Pdf();
    final sink = await FileSink.create(output);
    try {
      await pdf.merge(
        inputs.map<DataSource>((file) => FileSource(file)).toList(),
        sink,
      );
      await sink.close();
      return output;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<File> organizePdf(
    File source, {
    required List<int> pageOrder,
    required Map<int, int> rotations,
    String? password,
  }) async {
    if (pageOrder.isEmpty) {
      throw ArgumentError('At least one page must remain.');
    }

    final extracted = await _newFile('Organized_Work');
    final pdf1 = Pdf();
    final sink1 = await FileSink.create(extracted);
    try {
      await pdf1.extractPages(
        FileSource(source),
        sink1,
        pages: pageOrder,
        password: password,
      );
      await sink1.close();
    } catch (_) {
      await sink1.close();
      rethrow;
    } finally {
      await pdf1.dispose();
    }

    final normalizedRotations = <int, int>{
      for (final entry in rotations.entries)
        if (entry.value % 360 != 0) entry.key: entry.value,
    };

    if (normalizedRotations.isEmpty) return extracted;

    final output = await _newFile('Organized');
    final pdf2 = Pdf();
    final sink2 = await FileSink.create(output);
    try {
      await pdf2.rotatePages(
        FileSource(extracted),
        sink2,
        pages: normalizedRotations,
      );
      await sink2.close();
      try {
        await extracted.delete();
      } catch (_) {}
      return output;
    } catch (_) {
      await sink2.close();
      rethrow;
    } finally {
      await pdf2.dispose();
    }
  }

  Future<List<File>> splitRanges(
    File source,
    List<List<int>> ranges, {
    String? password,
  }) async {
    final outputs = <File>[];
    for (var i = 0; i < ranges.length; i++) {
      final pages = ranges[i];
      if (pages.isEmpty) continue;
      final output = await _newFile('Split_Range_${i + 1}');
      final pdf = Pdf();
      final sink = await FileSink.create(output);
      try {
        await pdf.extractPages(
          FileSource(source),
          sink,
          pages: pages,
          password: password,
        );
        await sink.close();
        outputs.add(output);
      } catch (_) {
        await sink.close();
        rethrow;
      } finally {
        await pdf.dispose();
      }
    }
    return outputs;
  }

  Future<File> unlockPdf(File source, String password) async {
    final output = await _newFile('Unlocked');
    final pdf = Pdf();
    final sink = await FileSink.create(output);
    try {
      await pdf.decrypt(
        FileSource(source),
        sink,
        password: password,
      );
      await sink.close();
      return output;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<File> protectPdfAdvanced(
    File source, {
    required String ownerPassword,
    String userPassword = '',
    bool readOnly = false,
  }) async {
    final output = await _newFile('Protected');
    final pdf = Pdf();
    final sink = await FileSink.create(output);
    try {
      await pdf.encrypt(
        FileSource(source),
        sink,
        encryption: PdfEncryptionConfig(
          ownerPassword: ownerPassword,
          userPassword: userPassword,
          algorithm: PdfEncryptionAlgorithm.aes256,
          permissions: readOnly
              ? const PdfPermissions.readOnly()
              : const PdfPermissions.all(),
        ),
      );
      await sink.close();
      return output;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<File> stampSignatureAt(
    File source,
    Uint8List signaturePng, {
    required int page,
    required PdfRect rect,
  }) async {
    final output = await _newFile('Signed');
    final pdf = Pdf();
    final sink = await FileSink.create(output);
    try {
      await pdf.addImageStamp(
        FileSource(source),
        sink,
        page: page,
        imageData: MemorySource(signaturePng),
        rect: rect,
      );
      await sink.close();
      return output;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<PdfDoc> openPdfDoc(
    Pdf pdf,
    File source, {
    String? password,
  }) {
    return pdf.open(FileSource(source), password: password);
  }


  Future<Uint8List?> renderFirstThumbnail(
    File source, {
    String? password,
    int width = 220,
  }) async {
    final pdf = Pdf();
    PdfDoc? doc;
    try {
      doc = await pdf.open(FileSource(source), password: password);
      await for (final page in doc.render(
        pages: const PdfPages.single(0),
        size: PdfRenderSize.thumbnail(width),
      )) {
        return page.data;
      }
      return null;
    } finally {
      await doc?.dispose();
      await pdf.dispose();
    }
  }

  Future<List<PdfPageInfo>> pageInfos(
    File source, {
    String? password,
  }) async {
    final pdf = Pdf();
    PdfDoc? doc;
    try {
      doc = await pdf.open(FileSource(source), password: password);
      return List<PdfPageInfo>.from(doc.pages);
    } finally {
      await doc?.dispose();
      await pdf.dispose();
    }
  }

}
