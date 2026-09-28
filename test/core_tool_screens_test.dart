import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/advanced_split_screen.dart';
import 'package:pdfmate/compression_screen.dart';
import 'package:pdfmate/page_organizer_screen.dart';
import 'package:pdfmate/pdf_service.dart';

void main() {
  late Directory root;
  late PdfService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pdfmate_widget_smoke_');
    final docs = await Directory('${root.path}/docs').create();
    final temp = await Directory('${root.path}/temp').create();
    service = PdfService(
      documentsDirectoryProvider: () async => docs,
      temporaryDirectoryProvider: () async => temp,
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  testWidgets('compression screen renders safe empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CompressionScreen(service: service)),
    );

    expect(find.text('Compress PDF'), findsOneWidget);
    expect(find.text('Choose a PDF'), findsOneWidget);
    expect(find.text('Compression level'), findsOneWidget);
  });

  testWidgets('advanced split screen exposes all split modes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AdvancedSplitScreen(service: service)),
    );

    expect(find.text('Advanced split'), findsOneWidget);
    expect(find.text('Each page'), findsOneWidget);
    expect(find.text('Every N'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
  });

  testWidgets('page organizer starts without eager thumbnails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PageOrganizerScreen(service: service)),
    );

    expect(find.text('Page organizer'), findsOneWidget);
    expect(find.text('No PDF selected'), findsOneWidget);
    expect(find.text('Choose PDF'), findsOneWidget);
  });
}

// Final QA branch trigger.
