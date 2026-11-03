import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: Pal.ember,
    onPrimary: Pal.onEmber,
    secondary: Pal.mint,
    onSecondary: Pal.onEmber,
    surface: Pal.surface,
    onSurface: Pal.text,
    error: Pal.rose,
    onError: Pal.onEmber,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Pal.canvas,
    canvasColor: Pal.canvas,
    dividerColor: Pal.line,
    fontFamily: Txt.ui,
    visualDensity: VisualDensity.standard,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Pal.overlay,
    textTheme: const TextTheme(
      displaySmall: Txt.headline,
      titleMedium: Txt.title,
      bodyMedium: Txt.body,
      bodySmall: Txt.meta,
      labelSmall: Txt.overline,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Pal.ember,
      selectionColor: Color(0x40E4693F),
      selectionHandleColor: Pal.ember,
    ),
    iconTheme: const IconThemeData(color: Pal.textMuted, size: 20),
    appBarTheme: const AppBarTheme(
      backgroundColor: Pal.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: Pal.text, size: 20),
      titleTextStyle: Txt.title,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Pal.surface,
      modalBackgroundColor: Pal.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Pal.raised,
      contentTextStyle: Txt.body.copyWith(fontSize: 13.5),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: Rd.md),
      insetPadding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x4),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Pal.ember,
        textStyle: Txt.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x2),
        minimumSize: const Size(0, 40),
        shape: const RoundedRectangleBorder(borderRadius: Rd.sm),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Pal.onEmber;
        return Pal.textMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Pal.ember;
        return Pal.overlay;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Pal.ember;
        return Pal.lineStrong;
      }),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Pal.ember,
      linearTrackColor: Pal.overlay,
      circularTrackColor: Pal.overlay,
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(3),
      radius: Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(Pal.lineStrong),
      trackColor: WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}
