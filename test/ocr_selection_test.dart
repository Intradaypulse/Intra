import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/ocr_screen.dart';
import 'package:pdfmate/pdf_service.dart';

class SelectionService extends PdfService {
  SelectionService({this.signed = false});
  final bool signed;
  final deleted = <String>[];
  var picks = 0;
  @override
  Future<File?> pickPdfFile() async =>
      File(++picks == 1 ? '/tmp/first.pdf' : '/tmp/invalid.pdf');
  @override
  Future<int> pageCount(File source, {String? password}) async {
    if (source.path.endsWith('invalid.pdf')) throw StateError('Invalid PDF');
    return 1;
  }

  @override
  Future<bool> hasDigitalSignatures(File source, {String? password}) async =>
      signed;
  @override
  Future<void> secureDeleteTemporary(File? file) async {
    if (file != null) deleted.add(file.path);
  }
}

void main() {
  testWidgets('OCR locks source controls during confirmation and unlocks on cancel', (tester) async {
    await tester.pumpWidget(MaterialApp(home: OcrScreen(service: SelectionService(signed: true))));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Make searchable'));
    await tester.tap(find.text('Make searchable'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Digitally signed PDF'), findsOneWidget);
    // Controls underneath the dialog must already be locked.
    final buttons = tester.widgetList<ButtonStyleButton>(find.byType(OutlinedButton, skipOffstage: false));
    expect(buttons.every((button) => button.onPressed == null), isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Digitally signed PDF'), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Make searchable')).onPressed, isNotNull);
  });

  testWidgets('invalid replacement leaves the previous OCR source usable', (
    tester,
  ) async {
    final service = SelectionService();
    await tester.pumpWidget(MaterialApp(home: OcrScreen(service: service)));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('first.pdf'), findsOneWidget);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('first.pdf'), findsOneWidget);
    expect(service.deleted, isNot(contains('/tmp/first.pdf')));
    expect(service.deleted, contains('/tmp/invalid.pdf'));
  });
}
