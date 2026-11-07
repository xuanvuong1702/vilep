import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Design tokens for Ví Lép.
///
/// Direction: Kickstarter's editorial confidence (big type, green progress,
/// pill CTAs) with a calmer, more premium surface treatment: warm off-white
/// canvas, hairline borders, low-shadow cards and one accent colour used
/// deliberately.
class V {
  // Brand
  static const green = Color(0xFF05CE78);
  static const greenDark = Color(0xFF059A5C);
  static const greenSoft = Color(0xFFE9FBF2);
  static const greenInk = Color(0xFF04170E);
  static const amber = Color(0xFFFFB020);
  static const amberSoft = Color(0xFFFFF7E6);
  static const danger = Color(0xFFE5484D);
  static const dangerSoft = Color(0xFFFDECEC);

  // Neutrals
  static const ink = Color(0xFF0B0B0C);
  static const ink2 = Color(0xFF3F3F46);
  static const inkSoft = ink2;
  static const muted = Color(0xFF71717A);
  static const faint = Color(0xFFA1A1AA);
  static const line = Color(0xFFECECE8);
  static const lineStrong = Color(0xFFDDDDD6);
  static const canvas = Color(0xFFF7F7F4);
  static const surface = Color(0xFFFFFFFF);

  // Spacing scale
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;

  // Radii
  static const double r12 = 12;
  static const double r14 = 14;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r24 = 24;
  static const double rPill = 999;

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x08101828), blurRadius: 16, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> floatingShadow = [
    BoxShadow(color: Color(0x14101828), blurRadius: 24, offset: Offset(0, 12)),
  ];

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 280);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'BeVietnamPro',
    colorScheme: ColorScheme.fromSeed(
      seedColor: V.green,
      primary: V.green,
      onPrimary: V.greenInk,
      surface: V.surface,
      onSurface: V.ink,
      error: V.danger,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: V.surface,
    splashFactory: InkSparkle.splashFactory,
  );

  const tight = -0.9;

  final text = base.textTheme.apply(bodyColor: V.ink, displayColor: V.ink).copyWith(
        displayLarge: const TextStyle(fontSize: 46, height: 1.02, fontWeight: FontWeight.w800, letterSpacing: -1.6, color: V.ink),
        displayMedium: const TextStyle(fontSize: 36, height: 1.06, fontWeight: FontWeight.w800, letterSpacing: -1.2, color: V.ink),
        headlineLarge: const TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1.0, color: V.ink),
        headlineMedium: const TextStyle(fontSize: 25, height: 1.16, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: V.ink),
        headlineSmall: const TextStyle(fontSize: 21, height: 1.22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: V.ink),
        titleLarge: const TextStyle(fontSize: 18, height: 1.28, fontWeight: FontWeight.w700, letterSpacing: -0.25, color: V.ink),
        titleMedium: const TextStyle(fontSize: 16, height: 1.32, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: V.ink),
        titleSmall: const TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600, color: V.ink),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.55, color: V.ink2),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.55, color: V.ink2),
        bodySmall: const TextStyle(fontSize: 12.5, height: 1.45, color: V.muted),
        labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0, color: V.ink),
        labelMedium: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: V.ink2),
        labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: V.muted),
      );

  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: V.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: V.ink,
        letterSpacing: tight,
        fontFamily: 'BeVietnamPro',
      ),
      iconTheme: IconThemeData(color: V.ink, size: 22),
      actionsIconTheme: IconThemeData(color: V.ink, size: 22),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: V.green,
        foregroundColor: V.greenInk,
        disabledBackgroundColor: V.line,
        disabledForegroundColor: V.faint,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(V.rPill)),
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: 0.1),
        elevation: 0,
        splashFactory: InkSparkle.splashFactory,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: V.ink,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: V.lineStrong, width: 1.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(V.rPill)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: V.ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: V.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      hintStyle: const TextStyle(color: V.faint, fontSize: 15, fontWeight: FontWeight.w500),
      labelStyle: const TextStyle(color: V.muted, fontSize: 14, fontWeight: FontWeight.w500),
      floatingLabelStyle: const TextStyle(color: V.greenDark, fontSize: 13, fontWeight: FontWeight.w600),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(V.r16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(V.r16), borderSide: const BorderSide(color: V.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(V.r16), borderSide: const BorderSide(color: V.green, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(V.r16), borderSide: const BorderSide(color: V.danger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(V.r16), borderSide: const BorderSide(color: V.danger, width: 1.6)),
      prefixIconColor: V.muted,
      suffixIconColor: V.muted,
    ),
    dividerTheme: const DividerThemeData(color: V.line, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: V.canvas,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(V.rPill)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: V.ink2, fontSize: 12.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: V.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13.5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(V.r12)),
      insetPadding: const EdgeInsets.all(16),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: V.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: V.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      showDragHandle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: V.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: V.ink, letterSpacing: -0.4, fontFamily: 'BeVietnamPro'),
      contentTextStyle: const TextStyle(fontSize: 14, height: 1.55, color: V.ink2, fontFamily: 'BeVietnamPro'),
    ),
    listTileTheme: const ListTileThemeData(iconColor: V.ink2, textColor: V.ink),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: V.green),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? V.green : V.lineStrong),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? V.green : V.lineStrong),
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

/// Layered gradient used behind case covers: brand-tinted, with a soft light
/// source so big emoji do not look pasted on.
LinearGradient coverGradient(String hex, {bool deep = false}) {
  final tint = colorFromHex(hex);
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: deep
        ? [Color.lerp(tint, Colors.white, 0.12)!, Color.lerp(tint, const Color(0xFF121212), 0.18)!]
        : [Color.lerp(tint, Colors.white, 0.55)!, tint],
  );
}
