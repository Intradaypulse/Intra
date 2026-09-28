import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_scan/document_scan.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdfw;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:printing/printing.dart';

import 'pdf_rules.dart';

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
  PdfService({
    Future<Directory> Function()? documentsDirectoryProvider,
    Future<Directory> Function()? temporaryDirectoryProvider,
  })  : _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory;

  final Future<Directory> Function() _documentsDirectoryProvider;
  final Future<Directory> Function() _temporaryDirectoryProvider;
  final Set<String> _managedTemporaryPaths = <String>{};

  final ImagePicker imagePicker = ImagePicker();

  Future<Directory> _docs() => _documentsDirectoryProvider();
  Future<Directory> _tmp() => _temporaryDirectoryProvider();

  Future<File> _newManagedTempFile(
    String prefix, {
    String extension = 'pdf',
  }) async {
    final dir = await _tmp();
    final file = File(
      '${dir.path}/pdfmate_secure_tmp_${_safe(prefix)}_'
      '${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    _managedTemporaryPaths.add(file.path);
    return file;
  }

  bool isManagedTemporaryFile(File file) =>
      _managedTemporaryPaths.contains(file.path) ||
      isPdfMateManagedTempPath(file.path);

  Future<void> secureDeleteTemporary(File? file) async {
    if (file == null || !isManagedTemporaryFile(file)) return;
    _managedTemporaryPaths.remove(file.path);
    try {
      if (!await file.exists()) return;
      final length = await file.length();
      if (length > 0) {
        final handle = await file.open(mode: FileMode.writeOnly);
        try {
          const chunkSize = 64 * 1024;
          final zeros = Uint8List(chunkSize);
          var remaining = length;
          while (remaining > 0) {
            final count = math.min(chunkSize, remaining).toInt();
            await handle.writeFrom(zeros, 0, count);
            remaining -= count;
          }
          await handle.flush();
        } finally {
          await handle.close();
        }
      }
      await file.delete();
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> cleanupStaleTemporaryFiles() async {
    final dir = await _tmp();
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && isPdfMateManagedTempPath(entity.path)) {
        _managedTemporaryPaths.add(entity.path);
        await secureDeleteTemporary(entity);
      }
    }
  }

  String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  Future<File> _newFile(String prefix) async {
    final dir = await _docs();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return File('${dir.path}/${_safe(prefix)}_$stamp.pdf');
  }



  Future<File> importPdfFile(String sourcePath, {String prefix = 'Scan'}) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Source PDF does not exist.', sourcePath);
    }
    final output = await _newFile(prefix);
    await source.copy(output.path);
    return output;
  }

  Future<String?> exportPdf(File source, String fileName) async {
    final name = fileName.toLowerCase().endsWith('.pdf')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    return FileSaver.instance.saveAs(
      name: name,
      filePath: source.path,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
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

    final output = await _newFile('Images');
    final pdf = Pdf();
    final sink = await FileSink.create(output);
    try {
      await pdf.imagesToPdf(
        [
          for (final image in images)
            FileSource(File(image.path)) as DataSource,
        ],
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
    final tmp = await _tmp();
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
    CompressionPreset preset, {
    String? password,
  }) async {
    final output = await _newFile('Compressed');
    final originalBytes = await source.length();
    File readable = source;
    File? decryptedTemp;

    try {
      if (password != null && password.isNotEmpty) {
        decryptedTemp = await decryptToTemporary(source, password);
        readable = decryptedTemp;
      }

      final pdf = Pdf();
      final sink = await FileSink.create(output);
      try {
        final policy = switch (preset) {
          CompressionPreset.highQuality => PdfImagePolicy.print,
          CompressionPreset.balanced => PdfImagePolicy.ebook,
          CompressionPreset.smallest => PdfImagePolicy.screen,
        };
        await pdf.compress(
          FileSource(readable),
          sink,
          images: policy,
        );
        await sink.close();
      } catch (_) {
        await sink.close();
        try {
          await output.delete();
        } catch (_) {}
        rethrow;
      } finally {
        await pdf.dispose();
      }

      return CompressionResult(
        file: output,
        originalBytes: originalBytes,
        outputBytes: await output.length(),
      );
    } finally {
      await secureDeleteTemporary(decryptedTemp);
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


  Future<List<File>> splitEveryN(
    File source,
    int every, {
    String? password,
  }) async {
    if (every < 1) throw ArgumentError.value(every, 'every');
    final count = await pageCount(source, password: password);
    final chunks = splitChunkCount(count, every);
    final files = <File>[];
    final sinks = <FileSink>[];
    File readable = source;
    File? decryptedTemp;

    try {
      if (password != null && password.isNotEmpty) {
        decryptedTemp = await decryptToTemporary(source, password);
        readable = decryptedTemp;
      }

      for (var i = 0; i < chunks; i++) {
        final file = await _newFile(
          every == 1 ? 'Page_${i + 1}' : 'Split_${i + 1}',
        );
        files.add(file);
        sinks.add(await FileSink.create(file));
      }

      final pdf = Pdf();
      try {
        await pdf.split(
          FileSource(readable),
          (index) => sinks[index],
          every: every,
        );
        for (final sink in sinks) {
          await sink.close();
        }
        return files;
      } catch (_) {
        for (final sink in sinks) {
          try {
            await sink.close();
          } catch (_) {}
        }
        for (final file in files) {
          try {
            await file.delete();
          } catch (_) {}
        }
        rethrow;
      } finally {
        await pdf.dispose();
      }
    } finally {
      await secureDeleteTemporary(decryptedTemp);
    }
  }

  Future<Uint8List?> renderPage(
    File source,
    int pageIndex, {
    String? password,
    int width = 1200,
  }) async {
    final pdf = Pdf();
    PdfDoc? doc;
    try {
      doc = await pdf.open(FileSource(source), password: password);
      await for (final page in doc.render(
        pages: PdfPages.single(pageIndex),
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


  Future<List<String>> ocrPdf(
    File source, {
    TextRecognitionScript script = TextRecognitionScript.latin,
    String? password,
  }) async {
    final pdf = Pdf();
    PdfDoc? doc;
    final recognizer = TextRecognizer(script: script);
    final texts = <String>[];
    try {
      doc = await pdf.open(FileSource(source), password: password);
      var index = 0;
      await for (final page in doc.render(
        pages: const PdfPages.all(),
        size: const PdfRenderSize(maxWidth: 1800, maxHeight: 2500),
      )) {
        final file = await _newManagedTempFile(
          'ocr_$index',
          extension: 'png',
        );
        await file.writeAsBytes(page.data, flush: true);
        try {
          final result = await recognizer.processImage(
            InputImage.fromFilePath(file.path),
          );
          texts.add(result.text);
        } finally {
          await secureDeleteTemporary(file);
        }
        index++;
      }
      return texts;
    } finally {
      await recognizer.close();
      await doc?.dispose();
      await pdf.dispose();
    }
  }

  Future<pw.Font> _ocrOverlayFont(TextRecognitionScript script) async {
    try {
      return switch (script) {
        TextRecognitionScript.chinese =>
          await PdfGoogleFonts.notoSansSCRegular(),
        TextRecognitionScript.devanagiri =>
          await PdfGoogleFonts.notoSansDevanagariRegular(),
        TextRecognitionScript.japanese =>
          await PdfGoogleFonts.notoSansJPRegular(),
        TextRecognitionScript.korean =>
          await PdfGoogleFonts.notoSansKRRegular(),
        TextRecognitionScript.latin =>
          await PdfGoogleFonts.notoSansRegular(),
      };
    } catch (error) {
      if (script == TextRecognitionScript.latin) {
        return pw.Font.helvetica();
      }
      throw StateError(
        'The Unicode OCR font could not be loaded. '
        'Connect to the internet once so PDFMate can cache the Noto font, '
        'then retry. Details: $error',
      );
    }
  }

  Future<bool> hasDigitalSignatures(
    File source, {
    String? password,
  }) async {
    final pdf = Pdf();
    PdfDoc? doc;
    try {
      doc = await pdf.open(FileSource(source), password: password);
      return (await doc.signatures).isNotEmpty;
    } finally {
      await doc?.dispose();
      await pdf.dispose();
    }
  }

  Future<File> _makeLatinSearchablePdfPreservingOriginal(
    File source, {
    String? password,
  }) async {
    final engine = Pdf();
    PdfDoc? doc;
    PdfEditor? editor;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final output = await _newFile('Searchable');
    var changed = false;

    try {
      doc = await engine.open(FileSource(source), password: password);
      editor = await engine.edit(FileSource(source), password: password);

      for (var index = 0; index < doc.pageCount; index++) {
        final existing =
            await doc.extract(pages: PdfPages.single(index));
        if (existing.trim().isNotEmpty) continue;

        Uint8List? pageBytes;
        await for (final rendered in doc.render(
          pages: PdfPages.single(index),
          size: const PdfRenderSize(maxWidth: 2200, maxHeight: 3200),
        )) {
          pageBytes = rendered.data;
          break;
        }
        if (pageBytes == null) continue;

        final decoded = img.decodePng(pageBytes);
        if (decoded == null) continue;

        final tempImage = await _newManagedTempFile(
          'latin_ocr_$index',
          extension: 'png',
        );
        await tempImage.writeAsBytes(pageBytes, flush: true);

        RecognizedText recognized;
        try {
          recognized = await recognizer.processImage(
            InputImage.fromFilePath(tempImage.path),
          );
        } finally {
          await secureDeleteTemporary(tempImage);
        }

        final info = doc.pages[index];
        final pageWidth = info.effectiveWidth;
        final pageHeight = info.effectiveHeight;

        for (final textBlock in recognized.blocks) {
          for (final line in textBlock.lines) {
            for (final element in line.elements) {
              final text = element.text.trim();
              if (text.isEmpty) continue;

              final placement = mapOcrRectToPdf(
                leftPx: element.boundingBox.left,
                topPx: element.boundingBox.top,
                widthPx: element.boundingBox.width,
                heightPx: element.boundingBox.height,
                imageWidthPx: decoded.width.toDouble(),
                imageHeightPx: decoded.height.toDouble(),
                pdfWidthPt: pageWidth,
                pdfHeightPt: pageHeight,
              );
              if (placement.width <= 0 || placement.height <= 0) continue;

              final yFromBottom =
                  math.max(0.0, pageHeight - placement.top - placement.height);

              await editor.addWatermark(
                index,
                text,
                style: PdfWatermarkStyle(
                  fontSize: math.max(2, placement.height * 0.82),
                  opacity: 0.001,
                  rotation: line.angle ?? 0,
                  color: PdfColor.black,
                ),
                position: PdfWatermarkPosition.exact(
                  x: placement.left,
                  y: yFromBottom,
                  width: placement.width,
                  height: placement.height,
                ),
                layer: PdfWatermarkLayer.background,
              );
              changed = true;
            }
          }
        }
      }

      if (!changed) {
        await source.copy(output.path);
        return output;
      }

      final sink = await FileSink.create(output);
      try {
        await editor.save(
          sink,
          options: const PdfSaveOptions.incremental(),
        );
        await sink.close();
      } catch (_) {
        await sink.close();
        try {
          await output.delete();
        } catch (_) {}
        rethrow;
      }
      return output;
    } finally {
      await recognizer.close();
      await editor?.dispose();
      await doc?.dispose();
      await engine.dispose();
    }
  }

  Future<File> _makeUnicodeSearchablePdf(
    File source, {
    required TextRecognitionScript script,
    String? password,
  }) async {
    final engine = Pdf();
    PdfDoc? doc;
    final recognizer = TextRecognizer(script: script);
    final output = await _newFile('Searchable');
    pw.Font? overlayFont;
    Pdf? assemblerEngine;
    PdfEditor? assembler;
    var generatedPages = 0;

    try {
      doc = await engine.open(FileSource(source), password: password);

      var allPagesAlreadySearchable = true;
      for (var index = 0; index < doc.pageCount; index++) {
        final existing =
            await doc.extract(pages: PdfPages.single(index));
        if (existing.trim().isEmpty) {
          allPagesAlreadySearchable = false;
          break;
        }
      }
      if (allPagesAlreadySearchable) {
        await source.copy(output.path);
        return output;
      }

      for (var index = 0; index < doc.pageCount; index++) {
        final existing =
            await doc.extract(pages: PdfPages.single(index));
        File pageFile;

        if (existing.trim().isNotEmpty) {
          pageFile = await _newManagedTempFile(
            'searchable_original_$index',
            extension: 'pdf',
          );
          final extractPdf = Pdf();
          final extractSink = await FileSink.create(pageFile);
          try {
            await extractPdf.extractPages(
              FileSource(source),
              extractSink,
              pages: [index],
              password: password,
            );
            await extractSink.close();
          } catch (_) {
            await extractSink.close();
            await secureDeleteTemporary(pageFile);
            rethrow;
          } finally {
            await extractPdf.dispose();
          }
        } else {
          Uint8List? renderedBytes;
          await for (final rendered in doc.render(
            pages: PdfPages.single(index),
            size: const PdfRenderSize(maxWidth: 2200, maxHeight: 3200),
          )) {
            renderedBytes = rendered.data;
            break;
          }
          final pageBytes = renderedBytes;
          if (pageBytes == null) continue;

          final decoded = img.decodePng(pageBytes);
          if (decoded == null) {
            throw StateError(
              'Could not decode rendered page ${index + 1}.',
            );
          }

          final tempImage = await _newManagedTempFile(
            'unicode_ocr_$index',
            extension: 'png',
          );
          await tempImage.writeAsBytes(pageBytes, flush: true);

          RecognizedText recognized;
          try {
            recognized = await recognizer.processImage(
              InputImage.fromFilePath(tempImage.path),
            );
          } finally {
            await secureDeleteTemporary(tempImage);
          }

          overlayFont ??= await _ocrOverlayFont(script);
          final info = doc.pages[index];
          final pageWidth = info.effectiveWidth;
          final pageHeight = info.effectiveHeight;
          final singlePage = pw.Document();
          final pageImage = pw.MemoryImage(pageBytes);
          final overlays = <pw.Widget>[];

          for (final textBlock in recognized.blocks) {
            for (final line in textBlock.lines) {
              for (final element in line.elements) {
                final text = element.text.trim();
                if (text.isEmpty) continue;

                final placement = mapOcrRectToPdf(
                  leftPx: element.boundingBox.left,
                  topPx: element.boundingBox.top,
                  widthPx: element.boundingBox.width,
                  heightPx: element.boundingBox.height,
                  imageWidthPx: decoded.width.toDouble(),
                  imageHeightPx: decoded.height.toDouble(),
                  pdfWidthPt: pageWidth,
                  pdfHeightPt: pageHeight,
                );
                if (placement.width <= 0 || placement.height <= 0) {
                  continue;
                }

                final angle = (line.angle ?? 0) * math.pi / 180;
                pw.Widget textWidget = pw.FittedBox(
                  fit: pw.BoxFit.fill,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    text,
                    maxLines: 1,
                    style: pw.TextStyle(
                      font: overlayFont,
                      fontSize: math.max(2, placement.height * 0.82),
                    ),
                  ),
                );
                if (angle.abs() > 0.001) {
                  textWidget = pw.Transform.rotate(
                    angle: angle,
                    child: textWidget,
                  );
                }

                overlays.add(
                  pw.Positioned(
                    left: placement.left,
                    top: placement.top,
                    child: pw.Container(
                      width: placement.width,
                      height: placement.height,
                      child: pw.Opacity(
                        opacity: 0.001,
                        child: textWidget,
                      ),
                    ),
                  ),
                );
              }
            }
          }

          singlePage.addPage(
            pw.Page(
              pageFormat: pdfw.PdfPageFormat(pageWidth, pageHeight),
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Stack(
                children: [
                  pw.Positioned.fill(
                    child: pw.Image(pageImage, fit: pw.BoxFit.fill),
                  ),
                  ...overlays,
                ],
              ),
            ),
          );

          pageFile = await _newManagedTempFile(
            'searchable_page_$index',
            extension: 'pdf',
          );
          await pageFile.writeAsBytes(
            await singlePage.save(),
            flush: true,
          );
        }

        assemblerEngine ??= Pdf();
        if (assembler == null) {
          assembler = await assemblerEngine.edit(FileSource(pageFile));
        } else {
          await assembler.mergeFrom(FileSource(pageFile));
        }
        generatedPages++;
        await secureDeleteTemporary(pageFile);
      }

      if (assembler == null || generatedPages == 0) {
        throw StateError('No pages were generated.');
      }

      final sink = await FileSink.create(output);
      try {
        await assembler.save(sink);
        await sink.close();
      } catch (_) {
        await sink.close();
        try {
          await output.delete();
        } catch (_) {}
        rethrow;
      }

      return output;
    } finally {
      await recognizer.close();
      await assembler?.dispose();
      await assemblerEngine?.dispose();
      await doc?.dispose();
      await engine.dispose();
    }
  }

  Future<pw.Font> _ocrFontForScript(
    TextRecognitionScript script,
  ) async {
    try {
      return switch (script) {
        TextRecognitionScript.devanagiri =>
          await PdfGoogleFonts.notoSansDevanagariRegular(),
        TextRecognitionScript.chinese =>
          await PdfGoogleFonts.notoSansSCRegular(),
        TextRecognitionScript.japanese =>
          await PdfGoogleFonts.notoSansJPRegular(),
        TextRecognitionScript.korean =>
          await PdfGoogleFonts.notoSansKRRegular(),
        _ => await PdfGoogleFonts.notoSansRegular(),
      };
    } catch (e) {
      if (script == TextRecognitionScript.latin) {
        return pw.Font.helvetica();
      }
      throw StateError(
        'Unicode OCR font could not be loaded. Connect to the internet once '
        'and retry so PDFMate can cache the required Noto font. Details: $e',
      );
    }
  }

  Future<bool> _allPagesAlreadySearchable(
    PdfDoc doc, {
    int minimumCharsPerPage = 3,
  }) async {
    if (doc.pageCount == 0) return false;
    for (var i = 0; i < doc.pageCount; i++) {
      final text = await doc.extract(pages: PdfPages.single(i));
      if (text.trim().length < minimumCharsPerPage) return false;
    }
    return true;
  }

  Future<File> makeSearchablePdf(
    File source, {
    TextRecognitionScript script = TextRecognitionScript.latin,
    String? password,
  }) async {
    final engine = Pdf();
    PdfDoc? doc;
    PdfEditor? editor;
    final recognizer = TextRecognizer(script: script);
    final output = await _newFile('Searchable');

    try {
      doc = await engine.open(FileSource(source), password: password);
      editor = await engine.edit(FileSource(source), password: password);

      for (var index = 0; index < doc.pageCount; index++) {
        Uint8List? renderedBytes;
        await for (final rendered in doc.render(
          pages: PdfPages.single(index),
          size: const PdfRenderSize(maxWidth: 2000, maxHeight: 2800),
        )) {
          renderedBytes = rendered.data;
          break;
        }

        final pageBytes = renderedBytes;
        if (pageBytes == null) continue;

        final decoded = img.decodePng(pageBytes);
        if (decoded == null) {
          throw StateError('Could not decode rendered page ${index + 1}.');
        }

        final tempImage = await _newManagedTempFile(
          'searchable_image_$index',
          extension: 'png',
        );
        await tempImage.writeAsBytes(pageBytes, flush: true);

        RecognizedText recognized;
        try {
          recognized = await recognizer.processImage(
            InputImage.fromFilePath(tempImage.path),
          );
        } finally {
          await secureDeleteTemporary(tempImage);
        }

        final info = doc.pages[index];

        for (final block in recognized.blocks) {
          for (final line in block.lines) {
            final parts = line.elements.isEmpty
                ? <({String text, Rect box})>[
                    (text: line.text, box: line.boundingBox),
                  ]
                : <({String text, Rect box})>[
                    for (final element in line.elements)
                      (text: element.text, box: element.boundingBox),
                  ];

            for (final part in parts) {
              final text = part.text.trim();
              if (text.isEmpty) continue;

              final placement = mapOcrRectToPdf(
                leftPx: part.box.left,
                topPx: part.box.top,
                widthPx: part.box.width,
                heightPx: part.box.height,
                imageWidthPx: decoded.width.toDouble(),
                imageHeightPx: decoded.height.toDouble(),
                pdfWidthPt: info.width,
                pdfHeightPt: info.height,
              );

              if (placement.width <= 0 || placement.height <= 0) continue;

              await editor.addWatermark(
                index,
                text,
                style: PdfWatermarkStyle(
                  fontSize: math.max(2, placement.height * 0.82),
                  opacity: 0.001,
                  rotation: line.angle ?? 0,
                ),
                position: PdfWatermarkPosition.exact(
                  x: placement.left,
                  y: placement.top,
                  width: placement.width,
                  height: placement.height,
                ),
                layer: PdfWatermarkLayer.background,
              );
            }
          }
        }
      }

      final sink = await FileSink.create(output);
      try {
        await editor.save(
          sink,
          options: const PdfSaveOptions.incremental(),
        );
        await sink.close();
      } catch (_) {
        await sink.close();
        try {
          await output.delete();
        } catch (_) {}
        rethrow;
      }

      return output;
    } finally {
      await recognizer.close();
      await editor?.dispose();
      await doc?.dispose();
      await engine.dispose();
    }
  }

  Future<File> decryptToTemporary(File source, String password) async {
    final output = await _newManagedTempFile('decrypted', extension: 'pdf');
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
      await secureDeleteTemporary(output);
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<File> createScannedPdfFromFiles(List<String> paths) async {
    if (paths.isEmpty) {
      throw ArgumentError('No scanned pages supplied.');
    }
    final output = await _newFile('Scan');
    final pdf = Pdf();
    final sink = await FileSink.create(output);
    try {
      await pdf.imagesToPdf(
        [
          for (final path in paths)
            FileSource(File(path)) as DataSource,
        ],
        sink,
      );
      await sink.close();
      return output;
    } catch (_) {
      await sink.close();
      try {
        if (await output.exists()) await output.delete();
      } catch (_) {}
      rethrow;
    } finally {
      await pdf.dispose();
      for (final path in paths) {
        try {
          final file = File(path);
          final name = file.uri.pathSegments.last;
          if (name.startsWith('pdfmate_scan_') && await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<String> savePdfToDownloads(File source) async {
    final rawName = source.uri.pathSegments.last;
    final name = rawName.toLowerCase().endsWith('.pdf')
        ? rawName.substring(0, rawName.length - 4)
        : rawName;
    final result = await FileSaver.instance.saveToDownloads(
      name: name,
      filePath: source.path,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
      subfolder: 'PDFMate',
    );
    if (result == null || result.trim().isEmpty) {
      throw FileSystemException(
        'Android did not confirm the Downloads copy.',
        source.path,
      );
    }
    return result;
  }

  Future<String> saveJpgToGallery(File source) async {
    final rawName = source.uri.pathSegments.last;
    final name = rawName.replaceFirst(
      RegExp(r'\.(jpg|jpeg)$', caseSensitive: false),
      '',
    );
    final result = await FileSaver.instance.saveToGallery(
      name: name,
      filePath: source.path,
      fileExtension: 'jpg',
      mimeType: MimeType.custom,
      customMimeType: 'image/jpeg',
      album: 'PDFMate',
    );
    if (result == null || result.trim().isEmpty) {
      throw FileSystemException(
        'Android did not confirm the Gallery copy.',
        source.path,
      );
    }
    return result;
  }

  Future<List<File>> pdfToJpgFromFile(
    File source, {
    String? password,
    int maxWidth = 2200,
    int maxHeight = 3100,
  }) async {
    final pdf = Pdf();
    PdfDoc? doc;
    final outputs = <File>[];

    try {
      doc = await pdf.open(FileSource(source), password: password);
      var pageNo = 1;
      await for (final page in doc.render(
        pages: const PdfPages.all(),
        size: PdfRenderSize(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
      )) {
        final decoded = img.decodePng(page.data);
        if (decoded == null) continue;
        final file = await _newManagedTempFile(
          'jpg_page_$pageNo',
          extension: 'jpg',
        );
        await file.writeAsBytes(
          img.encodeJpg(decoded, quality: 90),
          flush: true,
        );
        outputs.add(file);
        pageNo++;
      }
      return outputs;
    } catch (_) {
      for (final file in outputs) {
        await secureDeleteTemporary(file);
      }
      rethrow;
    } finally {
      await doc?.dispose();
      await pdf.dispose();
    }
  }
}
