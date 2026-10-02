import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/advanced_merge_screen.dart';
import 'package:pdfmate/advanced_split_screen.dart';
import 'package:pdfmate/pdf_service.dart';

class MetadataFile implements File {
  MetadataFile(this.path);
  @override
  final String path;
  @override
  Uri get uri => Uri.file(path);
  @override
  Future<int> length() async => 7;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PendingService extends PdfService {
  PendingService(this.files);
  final List<File> files;
  final operation = Completer<void>();
  final deleted = <String>[];
  @override
  Future<File?> pickPdfFile() async => files.first;
  @override
  Future<List<File>> pickPdfFiles() async => files;
  @override
  Future<int> pageCount(File source, {String? password}) async => 6;
  @override
  Future<Uint8List?> renderFirstThumbnail(File source, {
    String? password, int width = 220, PdfOperationControl? control,
  }) async => null;
  @override
  Future<File> mergeFiles(List<File> inputs) async {
    await operation.future;
    throw StateError('simulated I/O failure');
  }
  @override
  Future<List<File>> splitRanges(File source, List<List<int>> ranges, {
    String? password,
  }) async {
    await operation.future;
    throw StateError('simulated I/O failure');
  }
  @override
  Future<void> secureDeleteTemporary(File? file) async {
    if (file != null) deleted.add(file.path);
  }
}

void main() {
  for (final merge in [false, true]) {
    testWidgets('${merge ? 'Merge' : 'Split'} blocks Back while using its input', (tester) async {
      final files = <File>[MetadataFile('/temp/a.pdf'), MetadataFile('/temp/b.pdf')];
      final service = PendingService(files);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: navigator,
        home: const Scaffold(body: Text('Library'))));
      unawaited(navigator.currentState!.push<void>(MaterialPageRoute(builder: (_) => merge
        ? AdvancedMergeScreen(service: service)
        : AdvancedSplitScreen(service: service))));
      await tester.pumpAndSettle();
      await tester.tap(merge ? find.byTooltip('Add PDFs') : find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(merge ? 'Merge 2 PDFs' : 'Split PDF'));
      await tester.pump();
      await navigator.currentState!.maybePop();
      await tester.pump();
      expect(find.text(merge ? 'Merge PDFs' : 'Advanced split'), findsOneWidget);
      expect(service.deleted, isEmpty);
      service.operation.complete();
      await tester.pump();
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsOneWidget);
      expect(service.deleted, contains(files.first.path));
      expect(tester.takeException(), isNull);
    });
  }
}
