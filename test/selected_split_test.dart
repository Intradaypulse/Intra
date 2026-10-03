import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/advanced_split_screen.dart';
import 'package:pdfmate/pdf_service.dart';
class SelectedSplitService extends PdfService {
  List<List<int>>? requested;
  @override Future<File?> pickPdfFile() async => File('/tmp/example.pdf');
  @override Future<int> pageCount(File source, {String? password}) async => 10;
  @override Future<void> secureDeleteTemporary(File? file) async {}
  @override Future<List<File>> splitRanges(File source, List<List<int>> ranges, {String? password}) async {
    requested = ranges;
    return [File('/tmp/output.pdf')];
  }
}
void main() {
  testWidgets('page checkboxes create one PDF with sorted zero-based selection', (tester) async {
    final service = SelectedSplitService();
    await tester.pumpWidget(MaterialApp(home: AdvancedSplitScreen(service: service)));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '3'));
    await tester.tap(find.widgetWithText(CheckboxListTile, '1'));
    await tester.ensureVisible(find.text('Split PDF'));
    await tester.tap(find.text('Split PDF'));
    await tester.pumpAndSettle();
    expect(service.requested, [[0, 2]]);
  });
}
