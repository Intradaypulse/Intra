import 'dart:ui';
import 'package:flutter/material.dart';

ThemeData pdfMateTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Color(dark ? 0xFF91A7FF : 0xFF315EF5), brightness: brightness,
  ).copyWith(surface: Color(dark ? 0xFF000000 : 0xFFF7F8FC));
  return ThemeData(
    useMaterial3: true, colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(color: Color(dark ? 0xFF101116 : 0xFFFFFFFF),
      elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)))),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18))),
  );
}

/// Blur stays inside the card bounds; the black substrate remains OLED friendly.
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(borderRadius: BorderRadius.circular(22), child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: dark ? [const Color(0xE6222530), const Color(0xE60D0E12)]
            : [const Color(0xEEFFFFFF), const Color(0xCCEBF0FF)]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: dark ? Colors.white24 : Colors.white),
      ), child: child),
    ));
  }
}
