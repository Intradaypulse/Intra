import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:document_scan/document_scan.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:permission_handler/permission_handler.dart';

import 'pdf_rules.dart';
import 'ocr_layout.dart';
import 'scan_temp_session.dart';
import 'serial_executor.dart';

class PdfOperationCancelled implements Exception {
  @override
  String toString() => 'Operation cancelled.';
}

class PdfOperationControl {
  PdfOperationControl({this.onProgress, this.onCancel});
  final void Function(int completed, int total)? onProgress;
  void Function()? onCancel;
  bool _cancelled = false;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    onCancel?.call();
  }
  void check() {
    if (_cancelled) throw PdfOperationCancelled();
  }

  void progress(int completed, int total) {
    check();
    onProgress?.call(completed, total);
  }
}

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
  }) : _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory;

  final Future<Directory> Function() _documentsDirectoryProvider;
  final Future<Directory> Function() _temporaryDirectoryProvider;
  final Set<String> _managedTemporaryPaths = <String>{};
  static final Set<String> _activeTemporaryPaths = <String>{};

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
    _activeTemporaryPaths.add(file.path);
    return file;
  }

  bool isManagedTemporaryFile(File file) =>
      _managedTemporaryPaths.contains(file.path);

  Future<void> secureDeleteTemporary(File? file) async {
    if (file == null || !isManagedTemporaryFile(file)) return;
    _managedTemporaryPaths.remove(file.path);
    _activeTemporaryPaths.remove(file.path);
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
      if (entity is! File) continue;
      if (isPdfMateManagedTempPath(entity.path) &&
          !_activeTemporaryPaths.contains(entity.path)) {
        _managedTemporaryPaths.add(entity.path);
        await secureDeleteTemporary(entity);
      } else if (_isScanPageInTemp(entity, dir)) {
        // A scan still being assembled should not be removed by a second
        // PdfService instance. Old pages can survive process termination.
        final modified = await entity.lastModified();
        if (DateTime.now().difference(modified) > const Duration(hours: 1)) {
          await ScanTempSession().deletePath(entity.path);
        }
      }
    }
  }

  bool _isScanPageInTemp(File file, Directory temp) {
    final name = file.uri.pathSegments.last;
    return file.parent.absolute.path == temp.absolute.path &&
        RegExp(r'^pdfmate_scan_[A-Za-z0-9_-]+\.(jpg|jpeg|png)$').hasMatch(name);
  }

  String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  Future<File> _newFile(String prefix) async {
    final dir = await _docs();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return File('${dir.path}/${_safe(prefix)}_$stamp.pdf');
  }

  static final _renameQueue = SerialExecutor();

  Future<File> renamePdf(File source, String requestedName) =>
      _renameQueue.run(() => _renamePdf(source, requestedName));

  File renameDestination(File source, String requestedName) {
    final name = requestedName
        .trim()
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_');
    if (name.isEmpty || name == '.' || name == '..') {
      throw const FormatException('Enter a valid file name.');
    }
    return File('${source.parent.path}/$name.pdf');
  }

  Future<File> _renamePdf(File source, String requestedName) async {
    final destination = renameDestination(source, requestedName);
    if (source.absolute.path == destination.absolute.path) return source;
    // App rename actions are serialized; refuse existing destinations.
    if (await destination.exists()) {
      throw const FileSystemException('A PDF with this name already exists.');
    }
    return source.rename(destination.path);
  }

  Future<File> importPdfFile(
    String sourcePath, {
    String prefix = 'Scan',
  }) async {
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

  Future<Uint8List?> captureScannedPage({String filter = 'enhance'}) async {
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
      await pdf.imagesToPdf([
        for (final image in images) FileSource(File(image.path)) as DataSource,
      ], sink);
      await sink.close();
      return output;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
    }
  }

  Future<File> _imagesToPdfBytes(List<Uint8List> images, String prefix) async {
    final document = pw.Document();
    for (final bytes in images) {
      final image = pw.MemoryImage(bytes);
      document.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(14),
          build: (_) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
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
    final file = await _newManagedTempFile('picked');
    try {
      final path = picked.path;
      if (path != null && await File(path).exists()) {
        await File(path).openRead().pipe(file.openWrite());
      } else {
        await file.writeAsBytes(await picked.readAsBytes(), flush: true);
      }
      return file;
    } catch (_) {
      await secureDeleteTemporary(file);
      rethrow;
    }
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
      await secureDeleteTemporary(sourceFile);
    }
  }

  Future<File?> mergePdfs() async {
    final picked = await pickPdfs();
    if (picked.length < 2) return null;
    final inputs = <File>[];
    try {
      for (final item in picked) {
        inputs.add(await _materialize(item));
      }
    } catch (_) {
      for (final input in inputs) { await secureDeleteTemporary(input); }
      rethrow;
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
      for (final input in inputs) { await secureDeleteTemporary(input); }
    }
  }

  Future<List<File>> splitEveryPage() async {
    final picked = await pickPdf();
    if (picked == null) return const [];
    final sourceFile = await _materialize(picked);
    final pdf = Pdf();
    final sinks = <MemorySink>[];
    try {
      await pdf.split(FileSource(sourceFile), (index) {
        final sink = MemorySink();
        sinks.add(sink);
        return sink;
      }, every: 1);
      final outputs = <File>[];
      for (var i = 0; i < sinks.length; i++) {
        final file = await _newFile('Split_${i + 1}');
        await file.writeAsBytes(sinks[i].takeBytes(), flush: true);
        outputs.add(file);
      }
      return outputs;
    } finally {
      await pdf.dispose();
      await secureDeleteTemporary(sourceFile);
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
      await pdf.rotateAllPages(FileSource(sourceFile), sink, degrees: 90);
      await sink.close();
      return outputFile;
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      await pdf.dispose();
      await secureDeleteTemporary(sourceFile);
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
      await secureDeleteTemporary(sourceFile);
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
      await secureDeleteTemporary(sourceFile);
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
      await secureDeleteTemporary(sourceFile);
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
      await secureDeleteTemporary(sourceFile);
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
        if (decoded == null) throw StateError('Could not decode page $pageNo.');
        final jpgBytes = img.encodeJpg(decoded, quality: 88);
        final dir = await _docs();
        final path =
            '${dir.path}/PDF_Page_${pageNo}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(path);
        outputs.add(file);
        await file.writeAsBytes(jpgBytes, flush: true);
        pageNo++;
      }
      return outputs;
    } catch (_) {
      for (final output in outputs) {
        try {
          if (await output.exists()) await output.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      await doc?.dispose();
      await pdf.dispose();
      await secureDeleteTemporary(sourceFile);
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
      await secureDeleteTemporary(sourceFile);
    }
  }

  Future<(File, String)?> extractPdfTextToFile() async {
    final source = await pickPdfFile();
    if (source == null) return null;
    final output = await newTemporaryTextFile();
    final pdf = Pdf();
    PdfDoc? doc;
    IOSink? writer;
    final preview = StringBuffer();
    var previewLength = 0;
    try {
      doc = await pdf.open(FileSource(source));
      writer = output.openWrite();
      for (var i = 0; i < doc.pageCount; i++) {
        final text = await doc.extract(pages: PdfPages.single(i));
        writer.writeln('--- Page ${i + 1} ---');
        writer.writeln(text);
        if (previewLength < 50000) {
          final remaining = 50000 - previewLength;
          final excerpt = text.substring(0, text.length < remaining ? text.length : remaining);
          preview.writeln('--- Page ${i + 1} ---\n$excerpt\n');
          previewLength += excerpt.length;
        }
      }
      await writer.close();
      writer = null;
      return (output, preview.toString());
    } catch (_) {
      await secureDeleteTemporary(output);
      rethrow;
    } finally {
      try { await writer?.close(); } catch (_) {}
      await doc?.dispose();
      await pdf.dispose();
      await secureDeleteTemporary(source);
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
      await secureDeleteTemporary(sourceFile);
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
        await pdf.compress(FileSource(readable), sink, images: policy);
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
    if (pageOrder.isEmpty)
      throw ArgumentError('At least one page must remain.');
    final work = await _newManagedTempFile('organizer');
    final output = await _newFile('Organized');
    final engine = Pdf();
    try {
      final count = await pageCount(source, password: password);
      if (pageOrder.any((page) => page < 0 || page >= count)) {
        throw RangeError('A selected page is outside the document.');
      }
      if (rotations.entries.any(
        (entry) =>
            entry.key < 0 ||
            entry.key >= pageOrder.length ||
            entry.value % 90 != 0,
      )) {
        throw ArgumentError(
          'Page rotations must use valid output pages and multiples of 90 degrees.',
        );
      }
      final sink = await FileSink.create(work);
      try {
        await engine.extractPages(
          FileSource(source),
          sink,
          pages: pageOrder,
          password: password,
        );
      } finally {
        await sink.close();
      }
      final normalized = <int, int>{
        for (final entry in rotations.entries)
          if (entry.value % 360 != 0) entry.key: entry.value,
      };
      if (normalized.isEmpty) {
        await work.copy(output.path);
      } else {
        final sink = await FileSink.create(output);
        try {
          await engine.rotatePages(FileSource(work), sink, pages: normalized);
        } finally {
          await sink.close();
        }
      }
      return output;
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      await engine.dispose();
      await secureDeleteTemporary(work);
    }
  }

  Future<List<File>> splitRanges(
    File source,
    List<List<int>> ranges, {
    String? password,
  }) async {
    final outputs = <File>[];
    try {
    for (var i = 0; i < ranges.length; i++) {
      final pages = ranges[i];
      if (pages.isEmpty) continue;
      final output = await _newFile('Split_Range_${i + 1}');
      outputs.add(output);
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
      } catch (_) {
        await sink.close();
        rethrow;
      } finally {
        await pdf.dispose();
      }
    }
    return outputs;
    } catch (_) {
      for (final output in outputs) {
        try {
          if (await output.exists()) await output.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<File> unlockPdf(File source, String password) async {
    final output = await _newFile('Unlocked');
    final pdf = Pdf();
    final sink = await FileSink.create(output);
    try {
      await pdf.decrypt(FileSource(source), sink, password: password);
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

  Future<PdfDoc> openPdfDoc(Pdf pdf, File source, {String? password}) {
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

  Future<List<PdfPageInfo>> pageInfos(File source, {String? password}) async {
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
    final files = <File>[];
    final engine = Pdf();
    try {
      for (var start = 0; start < count; start += every) {
        final file = await _newFile(
          every == 1 ? 'Page_${start + 1}' : 'Split_${files.length + 1}',
        );
        files.add(file);
        final sink = await FileSink.create(file);
        try {
          await engine.extractPages(
            FileSource(source),
            sink,
            pages: [
              for (var i = start; i < math.min(start + every, count); i++) i,
            ],
            password: password,
          );
        } finally {
          await sink.close();
        }
      }
      return files;
    } catch (_) {
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    } finally {
      await engine.dispose();
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

  List<TextElement> _orderedOcrWords(
    RecognizedText text, {
    required bool tableRows,
  }) {
    if (tableRows) {
      return ocrReadingOrder([
        for (final block in text.blocks)
          for (final line in block.lines)
            for (final word in line.elements)
              OcrRegion(
                word,
                word.boundingBox.left,
                word.boundingBox.top,
                word.boundingBox.right,
                word.boundingBox.bottom,
              ),
      ], tableRows: true);
    }
    final blocks = ocrReadingOrder([
      for (final block in text.blocks)
        OcrRegion(
          block,
          block.boundingBox.left,
          block.boundingBox.top,
          block.boundingBox.right,
          block.boundingBox.bottom,
        ),
    ]);
    return [
      for (final block in blocks)
        for (final line in block.lines) ...line.elements,
    ];
  }

  Future<List<String>> ocrPdf(
    File source, {
    TextRecognitionScript script = TextRecognitionScript.latin,
    String? password,
    PdfOperationControl? control,
    bool tableRows = false,
    Future<void> Function(int index, String text)? onPageText,
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
        control?.progress(index, doc.pageCount);
        final file = await _newManagedTempFile('ocr_$index', extension: 'png');
        try {
          await file.writeAsBytes(page.data, flush: true);
          final result = await recognizer.processImage(
            InputImage.fromFilePath(file.path),
          );
          String pageText;
          if (tableRows) {
            pageText = _orderedOcrWords(
                result,
                tableRows: true,
              ).map((w) => w.text).join(' ');
          } else {
            final blocks = ocrReadingOrder([
              for (final block in result.blocks)
                OcrRegion(
                  block,
                  block.boundingBox.left,
                  block.boundingBox.top,
                  block.boundingBox.right,
                  block.boundingBox.bottom,
                ),
            ]);
            pageText = blocks
                  .map((b) => b.lines.map((l) => l.text).join('\n'))
                  .join('\n\n');
          }
          if (onPageText != null) {
            await onPageText(index, pageText);
          } else {
            texts.add(pageText);
          }
        } finally {
          await secureDeleteTemporary(file);
        }
        index++;
      }
      control?.check();
      return texts;
    } finally {
      await recognizer.close();
      await doc?.dispose();
      await pdf.dispose();
    }
  }

  Future<File> newTemporaryTextFile() =>
      _newManagedTempFile('ocr_text', extension: 'txt');

  Future<bool> hasDigitalSignatures(File source, {String? password}) async {
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

  Future<File> _makeSearchablePdfPreservingOriginal(
    File source, {
    required TextRecognitionScript script,
    String? password,
    PdfOperationControl? control,
    bool tableRows = false,
  }) async {
    final engine = Pdf();
    PdfDoc? doc;
    PdfEditor? editor;
    final recognizer = TextRecognizer(script: script);
    final output = await _newFile('Searchable');
    final verification = <int, List<String>>{};
    var changed = false;

    try {
      doc = await engine.open(FileSource(source), password: password);
      editor = await engine.edit(FileSource(source), password: password);

      for (var index = 0; index < doc.pageCount; index++) {
        control?.progress(index, doc.pageCount);
        final existing = await doc.extract(pages: PdfPages.single(index));
        final existingMatches = <String, List<SearchResult>>{};

        Uint8List? pageBytes;
        await for (final rendered in doc.render(
          pages: PdfPages.single(index),
          size: const PdfRenderSize(maxWidth: 2200, maxHeight: 3200),
        )) {
          pageBytes = rendered.data;
          break;
        }
        if (pageBytes == null)
          throw StateError('Could not render page ${index + 1}.');

        final decoded = img.decodePng(pageBytes);
        if (decoded == null)
          throw StateError('Could not decode page ${index + 1}.');

        final tempImage = await _newManagedTempFile(
          'native_ocr_$index',
          extension: 'png',
        );
        RecognizedText recognized;
        try {
          await tempImage.writeAsBytes(pageBytes, flush: true);
          recognized = await recognizer.processImage(
            InputImage.fromFilePath(tempImage.path),
          );
        } finally {
          await secureDeleteTemporary(tempImage);
        }

        final info = doc.pages[index];
        final pageWidth = info.effectiveWidth;
        final pageHeight = info.effectiveHeight;
        final pageTokens = <String>[];

        for (final element in _orderedOcrWords(
          recognized,
          tableRows: tableRows,
        )) {
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

          final yFromBottom = math.max(
            0.0,
            pageHeight - placement.top - placement.height,
          );

          if (existing.trim().isNotEmpty) {
            final matches = existingMatches[text] ??= await doc.search(
              query: text,
              pages: PdfPages.single(index),
            );
            final cx = placement.left + placement.width / 2;
            final cy = yFromBottom + placement.height / 2;
            if (matches.any(
              (m) =>
                  cx >= m.rect.x &&
                  cx <= m.rect.x + m.rect.width &&
                  cy >= m.rect.y &&
                  cy <= m.rect.y + m.rect.height,
            ))
              continue;
          }

          await editor.addWatermark(
            index,
            text,
            style: PdfWatermarkStyle(
              fontSize: math.max(2, placement.height * 0.82),
              opacity: 0.001,
              rotation: element.angle ?? 0,
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

          if (text.isNotEmpty) {
            pageTokens.add(text);
          }
          changed = true;
        }

        if (pageTokens.isNotEmpty) verification[index] = pageTokens;
      }

      if (!changed) {
        await source.copy(output.path);
        control?.check();
        return output;
      }

      control?.check();
      final sink = await FileSink.create(output);
      try {
        await editor.save(sink, options: const PdfSaveOptions.incremental());
        await sink.close();
      } catch (_) {
        await sink.close();
        try {
          await output.delete();
        } catch (_) {}
        rethrow;
      }

      // The native editor preserves the original page objects, annotations,
      // forms, bookmarks and vector content. Confirm that the invisible OCR
      // text actually survives extraction for the selected script. If an OEM
      // PDF engine cannot encode a script, verification rejects the output.
      if (verification.isNotEmpty) {
        final verifier = Pdf();
        PdfDoc? verifyDoc;
        try {
          verifyDoc = await verifier.open(
            FileSource(output),
            password: password,
          );
          for (final entry in verification.entries) {
            final extracted = await verifyDoc.extract(
              pages: PdfPages.single(entry.key),
            );
            final normalized = extracted.replaceAll(RegExp(r'\s+'), '');
            final matched = entry.value.every(
              (token) =>
                  normalized.contains(token.replaceAll(RegExp(r'\s+'), '')),
            );
            if (!matched) {
              throw StateError(
                'Native searchable-PDF text verification failed on '
                'page ${entry.key + 1}.',
              );
            }
          }
        } finally {
          await verifyDoc?.dispose();
          await verifier.dispose();
        }
      }

      control?.check();
      return output;
    } catch (_) {
      // An extraction/encoding failure must not leave a misleading partial
      // "searchable" document in the user's library.
      try {
        if (await output.exists()) await output.delete();
      } catch (_) {}
      rethrow;
    } finally {
      await recognizer.close();
      await editor?.dispose();
      await doc?.dispose();
      await engine.dispose();
    }
  }

  Future<File> makeSearchablePdf(
    File source, {
    TextRecognitionScript script = TextRecognitionScript.latin,
    String? password,
    PdfOperationControl? control,
    bool tableRows = false,
  }) async {
    if (script == TextRecognitionScript.devanagiri) {
      return _makeDevanagariSearchablePdf(
        source,
        password: password,
        control: control,
        tableRows: tableRows,
      );
    }
    return _makeSearchablePdfPreservingOriginal(
      source,
      script: script,
      password: password,
      control: control,
      tableRows: tableRows,
    );
  }

  /// Add an invisible embedded-font layer in an incremental revision. Only
  /// OCR geometry is spooled; rendered page images are deleted immediately.
  Future<File> _makeDevanagariSearchablePdf(
    File source, {
    String? password,
    PdfOperationControl? control,
    bool tableRows = false,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Preserving Hindi OCR currently requires Android.',
      );
    }
    final engine = Pdf();
    PdfDoc? doc;
    final recognizer = TextRecognizer(script: TextRecognitionScript.devanagiri);
    final output = await _newFile('Searchable_Hindi');
    final manifest = await _newManagedTempFile(
      'ocr_geometry',
      extension: 'jsonl',
    );
    IOSink? writer;
    final token = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      doc = await engine.open(FileSource(source), password: password);
      writer = manifest.openWrite();
      for (var index = 0; index < doc.pageCount; index++) {
        control?.progress(index, doc.pageCount);
        Uint8List? bytes;
        await for (final page in doc.render(
          pages: PdfPages.single(index),
          size: const PdfRenderSize(maxWidth: 1800, maxHeight: 2500),
        )) {
          bytes = page.data;
          break;
        }
        if (bytes == null)
          throw StateError('Could not render page ${index + 1}.');
        final image = img.decodePng(bytes);
        if (image == null)
          throw StateError('Could not decode page ${index + 1}.');
        final input = await _newManagedTempFile('ocr_input', extension: 'png');
        RecognizedText recognized;
        try {
          await input.writeAsBytes(bytes, flush: true);
          recognized = await recognizer.processImage(
            InputImage.fromFilePath(input.path),
          );
        } finally {
          await secureDeleteTemporary(input);
        }
        final info = doc.pages[index];
        final existing = await doc.extract(pages: PdfPages.single(index));
        final existingMatches = <String, List<SearchResult>>{};
        final words = <Map<String, Object>>[];
        for (final word in _orderedOcrWords(recognized, tableRows: tableRows)) {
          if (word.text.trim().isEmpty) continue;
          final box = word.boundingBox;
          if (box.width <= 0 || box.height <= 0) continue;
          if (existing.trim().isNotEmpty) {
            final matches = existingMatches[word.text] ??= await doc.search(
              query: word.text,
              pages: PdfPages.single(index),
            );
            final cx = box.center.dx * info.effectiveWidth / image.width;
            final cy =
                info.effectiveHeight -
                box.center.dy * info.effectiveHeight / image.height;
            if (matches.any(
              (m) =>
                  cx >= m.rect.x &&
                  cx <= m.rect.right &&
                  cy >= m.rect.y &&
                  cy <= m.rect.bottom,
            ))
              continue;
          }
          words.add(
            ocrWordGeometry(
              text: word.text,
              corners: word.cornerPoints,
              left: box.left,
              top: box.top,
              width: box.width,
              height: box.height,
              scaleX: info.effectiveWidth / image.width,
              scaleY: info.effectiveHeight / image.height,
              angle: word.angle ?? 0,
            ),
          );
        }
        writer.writeln(jsonEncode({'page': index, 'words': words}));
        await writer.flush();
      }
      await writer.close();
      writer = null;
      await doc.dispose();
      doc = null;
      control?.check();
      control?.onCancel = () {
        unawaited(const MethodChannel('pdfmate/unicode_overlay')
            .invokeMethod<void>('cancel', {'token': token})
            .catchError((Object _) {}));
      };
      await const MethodChannel(
        'pdfmate/unicode_overlay',
      ).invokeMethod<void>('append', {
        'source': source.path,
        'output': output.path,
        'manifest': manifest.path,
        'password': password,
        'token': token,
      });
      control?.check();
      return output;
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      control?.onCancel = null;
      // A full disk can fail both flush and close; cleanup must still run.
      try {
        await writer?.close();
      } catch (_) {}
      await secureDeleteTemporary(manifest);
      await recognizer.close();
      await doc?.dispose();
      await engine.dispose();
    }
  }

  Future<File> decryptToTemporary(File source, String password) async {
    final output = await _newManagedTempFile('decrypted', extension: 'pdf');
    final pdf = Pdf();
    final sink = await FileSink.create(output);
    try {
      await pdf.decrypt(FileSource(source), sink, password: password);
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
      await pdf.imagesToPdf([
        for (final path in paths) FileSource(File(path)) as DataSource,
      ], sink);
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
      final temp = await _tmp();
      for (final path in paths) {
        try {
          final file = File(path);
          if (_isScanPageInTemp(file, temp) && await file.exists()) {
            await ScanTempSession().deletePath(path);
          }
        } catch (_) {}
      }
    }
  }

  Future<T> _withLegacyStoragePermission<T>(
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on PlatformException catch (error) {
      final details = '${error.code} ${error.message ?? ''}'.toLowerCase();
      final legacyStorageDenied =
          Platform.isAndroid &&
          (details.contains('write_external_storage') ||
              details.contains('read_external_storage') ||
              details.contains('permission') && details.contains('storage'));

      if (!legacyStorageDenied) rethrow;

      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw FileSystemException(
          'Storage permission is required on Android 9 and below to save '
          'a shared Downloads/Gallery copy.',
        );
      }

      return operation();
    }
  }

  Future<String> savePdfToDownloads(File source) async {
    final rawName = source.uri.pathSegments.last;
    final name = rawName.toLowerCase().endsWith('.pdf')
        ? rawName.substring(0, rawName.length - 4)
        : rawName;
    final result = await _withLegacyStoragePermission(
      () => FileSaver.instance.saveToDownloads(
        name: name,
        filePath: source.path,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
        subfolder: 'PDFMate',
      ),
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
    final result = await _withLegacyStoragePermission(
      () => FileSaver.instance.saveToGallery(
        name: name,
        filePath: source.path,
        fileExtension: 'jpg',
        mimeType: MimeType.custom,
        customMimeType: 'image/jpeg',
        album: 'PDFMate',
      ),
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
    int startPage = 0,
    int? endPage,
    PdfOperationControl? control,
  }) async {
    final pdf = Pdf();
    PdfDoc? doc;
    final outputs = <File>[];

    try {
      doc = await pdf.open(FileSource(source), password: password);
      final last = endPage ?? doc.pageCount;
      if (startPage < 0 || last > doc.pageCount || startPage >= last) {
        throw RangeError('Choose a valid page range.');
      }
      for (var index = startPage; index < last; index++) {
        control?.progress(index - startPage, last - startPage);
        final pageNo = index + 1;
        await for (final page in doc.render(
          pages: PdfPages.single(index),
          size: PdfRenderSize(maxWidth: maxWidth, maxHeight: maxHeight),
        )) {
        final decoded = img.decodePng(page.data);
        if (decoded == null) throw StateError('Could not decode page $pageNo.');
        final file = await _newManagedTempFile(
          'jpg_page_$pageNo',
          extension: 'jpg',
        );
        outputs.add(file);
        await file.writeAsBytes(
          img.encodeJpg(decoded, quality: 90),
          flush: true,
        );
        }
      }
      control?.check();
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
