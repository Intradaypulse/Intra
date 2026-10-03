import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfmate/app_theme.dart';
void main() {
  test('dark theme uses true black for the scaffold and readable foreground', () {
    final theme = pdfMateTheme(Brightness.dark);
    expect(theme.scaffoldBackgroundColor, Colors.black);
    expect(theme.colorScheme.onSurface.computeLuminance(), greaterThan(.5));
  });
}
