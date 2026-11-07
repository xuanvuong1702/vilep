import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Kickstarter-inspired design tokens: white canvas, near-black ink,
/// signature green progress, pill buttons and generous rounded corners.
class V {
  static const green = Color(0xFF05CE78);
  static const greenDark = Color(0xFF05A863);
  static const greenSoft = Color(0xFFE7FBF2);
  static const ink = Color(0xFF0B0B0B);
  static const inkSoft = Color(0xFF3D3D3D);
  static const muted = Color(0xFF737373);
  static const line = Color(0xFFE7E7E4);
  static const canvas = Color(0xFFF7F7F5);
  static const surface = Color(0xFFFFFFFF);
  static const amber = Color(0xFFFFB020);
  static const danger = Color(0xFFE5484D);

  static const double radius = 18;
  static const double pad = 20;
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'BeVietnamPro',
    colorScheme: ColorScheme.fromSeed(
      seedColor: V.green,
      primary: V.green,
      surface: V.surface,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: V.surface,
    splashFactory: InkSparkle.splashFactory,
  );

  final text = base.textTheme.apply(bodyColor: V.ink, displayColor: V.ink).copyWith(
        displayLarge: const TextStyle(fontSize: 44, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: -1.4, color: V.ink),
        displayMedium: const TextStyle(fontSize: 34, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1, color: V.ink),
        headlineLarge: const TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: V.ink),
        headlineMedium: const TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: V.ink),
        headlineSmall: const TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: V.ink),
        titleLarge: const TextStyle(fontSize: 18, height: 1.3, fontWeight: FontWeight.w700, color: V.ink),
        titleMedium: const TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w600, color: V.ink),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.5, color: V.ink),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.5, color: V.inkSoft),
        bodySmall: const TextStyle(fontSize: 12.5, height: 1.45, color: V.muted),
        labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1, color: V.ink),
      );

  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: V.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: V.ink, letterSpacing: -0.4),
      iconTheme: IconThemeData(color: V.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: V.green,
        foregroundColor: const Color(0xFF04170E),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.1),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: V.ink,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: V.line, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: V.ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: V.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: V.muted, fontSize: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: V.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: V.green, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: V.danger)),
    ),
    dividerTheme: const DividerThemeData(color: V.line, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: V.canvas,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: V.inkSoft),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: V.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: V.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
    }),
  );
}

Color colorFromHex(String hex) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6) return V.greenSoft;
  return Color(int.parse('FF$cleaned', radix: 16));
}
