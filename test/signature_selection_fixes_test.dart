import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdfmate/pdf_service.dart';
import 'package:pdfmate/signature_placement_screen.dart';
import 'package:pdfmate/ocr_page_preview_screen.dart';
import 'package:pdfmate/signature_screen.dart';
import 'package:pdfmate/signature_store.dart';
import 'package:signature/signature.dart';

Uint8List png(int w, int h) =>
    Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

class SignService extends PdfService {
  @override
  Future<File?> pickPdfFile() async => File('/tmp/audit.pdf');
  @override
  Future<bool> hasDigitalSignatures(File f, {String? password}) async => false;
  @override
  Future<List<PdfPageInfo>> pageInfos(File f, {String? password}) async => [
    const PdfPageInfo(index: 0, width: 600, height: 800, rotation: 0),
  ];
  @override
  Future<PdfRect> pageVisibleBox(File f, int page, {String? password}) async =>
      PdfRect(x: 0, y: 0, width: 600, height: 800);
  @override
  Future<Uint8List?> renderPage(
    File f,
    int page, {
    String? password,
    int width = 1000,
    PdfOperationControl? control,
  }) async => png(60, 80);
  @override
  Future<void> secureDeleteTemporary(File? f) async {}
}

class AuthSignService extends SignService {
  AuthSignService({this.signed = false, this.ownerRequired = false});
  final bool signed, ownerRequired;
  final attempts = <String?>[];
  @override
  Future<bool> hasDigitalSignatures(File f, {String? password}) async => signed;
  @override
  Future<File> stampSignatureAt(
    File source,
    Uint8List png, {
    required int page,
    required PdfRect rect,
    String? password,
  }) async {
    attempts.add(password);
    if (ownerRequired && password != 'owner') {
      throw PlatformException(
        code: password == null
            ? 'OCR_OWNER_PASSWORD_REQUIRED'
            : 'OCR_WRONG_PASSWORD',
      );
    }
    return File('/tmp/signed.pdf');
  }
}

class TextService extends PdfService {
  TextService({this.bottom = false});
  final bool bottom;
  @override
  Future<OcrPagePreview> recognizePage(
    File f,
    int page, {
    TextRecognitionScript? script,
    String? password,
    PdfOperationControl? control,
  }) async => OcrPagePreview(
    bytes: png(200, 200),
    width: 200,
    height: 200,
    script: TextRecognitionScript.latin,
    text: RecognizedText(
      text: 'I\nOther',
      blocks: [
        for (final (word, r) in [
          ('I', Rect.fromLTWH(10, bottom ? 180 : 30, 4, 20)),
          if (!bottom) ('Other', const Rect.fromLTWH(100, 90, 70, 20)),
        ])
          TextBlock(
            text: word,
            boundingBox: r,
            recognizedLanguages: [],
            cornerPoints: [],
            lines: [
              TextLine(
                text: word,
                boundingBox: r,
                elements: [],
                recognizedLanguages: [],
                cornerPoints: [],
                confidence: 1,
                angle: 0,
              ),
            ],
          ),
      ],
    ),
  );
}

void main() {
  Future<void> openSigning(WidgetTester t, SignService service) async {
    await t.pumpWidget(
      MaterialApp(
        home: SignaturePlacementScreen(
          service: service,
          initialSignature: png(100, 40),
        ),
      ),
    );
    await t.tap(find.text('Choose PDF'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
  }

  testWidgets('owner password retries and cancel stops stamping', (t) async {
    final service = AuthSignService(ownerRequired: true);
    await openSigning(t, service);
    expect(find.text('Owner password required'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'wrong');
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    expect(find.text('Wrong owner password. Try again'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(service.attempts, [null, 'wrong']);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'owner');
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    expect(service.attempts.last, 'owner');
    expect(find.textContaining('Signature failed:'), findsNothing);
  });

  testWidgets('digitally signed PDF requires consent before stamping', (
    t,
  ) async {
    final service = AuthSignService(signed: true);
    await openSigning(t, service);
    expect(find.text('Digitally signed PDF'), findsOneWidget);
    expect(service.attempts, isEmpty);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(service.attempts, isEmpty);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    await t.tap(find.text('Create copy'));
    await t.pumpAndSettle();
    expect(service.attempts, [null]);
  });

  testWidgets('a deleted signature can be saved again from the same drawing', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final root = (await t.runAsync(
      () => Directory.systemTemp.createTemp('audit_signature_'),
    ))!;
    final store = SignatureStore(directoryProvider: () async => root);
    try {
      await t.pumpWidget(MaterialApp(home: SignatureScreen(store: store)));
      await t.dragFrom(
        t.getCenter(find.byType(Signature)),
        const Offset(90, 30),
      );
      await t.runAsync(() async {
        await t.tap(find.text('Save signature'));
        await t.pump();
        for (var i = 0; i < 50 && (await store.load()).isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await t.pumpAndSettle();
      expect((await t.runAsync(store.load))!.length, 1);
      await t.runAsync(() async {
        await t.tap(find.byTooltip('Saved signatures'));
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await t.pump();
      });
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.byTooltip('Delete saved signature'));
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await t.pump();
      });
      await t.pumpAndSettle();
      await t.tap(find.text('Close'));
      await t.pumpAndSettle();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save signature'),
            )
            .onPressed,
        isNotNull,
      );
      await t.runAsync(() async {
        await t.tap(find.text('Save signature'));
        await t.pump();
        for (var i = 0; i < 50 && (await store.load()).isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await t.pump();
      });
      await t.pumpAndSettle();
      expect(await t.runAsync(store.load), hasLength(1));
      expect(find.text('Signature saved for reuse.'), findsOneWidget);
    } finally {
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => root.delete(recursive: true));
    }
  });

  testWidgets('landscape signing layout stays within the viewport', (t) async {
    t.view.physicalSize = const Size(800, 360);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: SignaturePlacementScreen(
          service: SignService(),
          initialSignature: png(100, 40),
        ),
      ),
    );
    await t.tap(find.text('Choose PDF'));
    await t.pumpAndSettle();
    final errors = <Object>[];
    Object? e;
    while ((e = t.takeException()) != null) {
      errors.add(e!);
    }
    expect(errors, isEmpty);
  });
  testWidgets('bottom-line selection handles stay touchable', (t) async {
    final semantics = t.ensureSemantics();
    try {
      await t.pumpWidget(
        MaterialApp(
          home: OcrPagePreviewScreen(
            service: TextService(bottom: true),
            source: File('/tmp/audit.pdf'),
            pageCount: 1,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.longPress(find.bySemanticsLabel('I'));
      await t.pump();
      expect(find.bySemanticsLabel('Selection end'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Selection end').hitTestable(),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('short-word start handle adjusts the correct endpoint', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData')
          copied = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    try {
      await t.pumpWidget(
        MaterialApp(
          home: OcrPagePreviewScreen(
            service: TextService(),
            source: File('/tmp/audit.pdf'),
            pageCount: 1,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.longPress(find.bySemanticsLabel('I'));
      await t.pump();
      final start = find.bySemanticsLabel('Selection start');
      final target = t.getCenter(find.bySemanticsLabel('Other'));
      await t.drag(start, target - t.getCenter(start));
      await t.pump();
      await t.tap(find.text('Copy selected'));
      await t.pumpAndSettle();
      // Crossing the end collapses the selection at the dragged word.
      expect(copied, 'Other');
    } finally {
      semantics.dispose();
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    }
  });
}
