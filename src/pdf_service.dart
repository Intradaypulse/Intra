import 'dart:io';
import 'dart:typed_data';

import 'package:document_scan/document_scan.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdf_manipulator/io.dart';

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
}
