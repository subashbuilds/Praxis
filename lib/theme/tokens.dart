import 'package:flutter/material.dart';

/// Praxis palette. Two complete readings of the same product: warm graphite
/// by night and warm paper by day. Colours are resolved at build time from the
/// active brightness so every legacy surface follows the theme.
class Pal {
  const Pal._();

  static bool _dark = true;
  static bool get isDark => _dark;
  static void use(Brightness brightness) {
    _dark = brightness == Brightness.dark;
  }

  static Color get canvas =>
      _dark ? const Color(0xFF0A0908) : const Color(0xFFF7F3EC);
  static Color get surface =>
      _dark ? const Color(0xFF12100E) : const Color(0xFFFFFFFF);
  static Color get raised =>
      _dark ? const Color(0xFF1A1714) : const Color(0xFFF0EAE1);
  static Color get overlay =>
      _dark ? const Color(0xFF241F1B) : const Color(0xFFE8E0D6);

  static Color get line =>
      _dark ? const Color(0xFF2C2621) : const Color(0xFFE4DBD0);
  static Color get lineStrong =>
      _dark ? const Color(0xFF3B342D) : const Color(0xFFCEC2B5);

  static Color get text =>
      _dark ? const Color(0xFFF4EFE9) : const Color(0xFF1C1916);
  static Color get textMuted =>
      _dark ? const Color(0xFFB7ADA2) : const Color(0xFF5E564D);
  static Color get textDim =>
      _dark ? const Color(0xFF877E74) : const Color(0xFF887C70);

  static Color get ember =>
      _dark ? const Color(0xFFE4693F) : const Color(0xFFC0512C);
  static Color get emberDeep =>
      _dark ? const Color(0xFFB94723) : const Color(0xFF9A3C1E);
  static Color get onEmber =>
      _dark ? const Color(0xFF1A0E08) : const Color(0xFFFFF8F3);

  static Color get mint =>
      _dark ? const Color(0xFF7FD1A8) : const Color(0xFF267354);
  static Color get amber =>
      _dark ? const Color(0xFFE8B45C) : const Color(0xFF8A5F12);
  static Color get rose =>
      _dark ? const Color(0xFFF07A6E) : const Color(0xFFB23B36);
  static Color get sky =>
      _dark ? const Color(0xFF8AB4F0) : const Color(0xFF2F5F9E);

  static Color get terminal =>
      _dark ? const Color(0xFF070706) : const Color(0xFFFBF8F3);

  /// GitHub code palette: dark in both modes when the app is dark, light when
  /// the app is light. Syntax colours follow GitHub's own themes.
  static Color get ghBg =>
      _dark ? const Color(0xFF0D1117) : const Color(0xFFFFFFFF);
  static Color get ghPanel =>
      _dark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
  static Color get ghLine =>
      _dark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
  static Color get ghText =>
      _dark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
  static Color get ghMuted =>
      _dark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
  static Color get ghKeyword =>
      _dark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E);
  static Color get ghString =>
      _dark ? const Color(0xFFA5D6FF) : const Color(0xFF0A3069);
  static Color get ghNumber =>
      _dark ? const Color(0xFF79C0FF) : const Color(0xFF0550AE);
  static Color get ghTag =>
      _dark ? const Color(0xFF7EE787) : const Color(0xFF116329);
  static Color get ghAttr =>
      _dark ? const Color(0xFFD2A8FF) : const Color(0xFF8250DF);
  static Color get ghAddBg =>
      _dark ? const Color(0xFF12261E) : const Color(0xFFE6FFEC);
  static Color get ghAddText =>
      _dark ? const Color(0xFF7EE787) : const Color(0xFF1A7F37);
  static Color get ghDelBg =>
      _dark ? const Color(0xFF2D1417) : const Color(0xFFFFEBE9);
  static Color get ghDelText =>
      _dark ? const Color(0xFFFFA198) : const Color(0xFFCF222E);
}

/// Type roles. Inter for interface, JetBrains Mono for anything the machine
/// produced, Lora for the editorial moments in the app.
class Txt {
  const Txt._();

  static const ui = 'Inter';
  static const mono = 'JetBrainsMono';
  static const serif = 'Lora';

  static TextStyle get display => TextStyle(
        fontFamily: serif,
        fontSize: 30,
        height: 1.14,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.4,
        color: Pal.text,
      );

  static TextStyle get headline => TextStyle(
        fontFamily: ui,
        fontSize: 25,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: Pal.text,
      );

  static TextStyle get title => TextStyle(
        fontFamily: ui,
        fontSize: 16.5,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: Pal.text,
      );

  static TextStyle get body => TextStyle(
        fontFamily: ui,
        fontSize: 14,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: Pal.text,
      );

  static TextStyle get bodySoft => TextStyle(
        fontFamily: ui,
        fontSize: 13.5,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: Pal.textMuted,
      );

  static TextStyle get label => TextStyle(
        fontFamily: ui,
        fontSize: 12.5,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: Pal.textMuted,
      );

  static TextStyle get meta => TextStyle(
        fontFamily: mono,
        fontSize: 11,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: Pal.textDim,
        letterSpacing: 0.1,
      );

  static TextStyle get overline => TextStyle(
        fontFamily: mono,
        fontSize: 10,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
        color: Pal.textDim,
      );

  static TextStyle get code => TextStyle(
        fontFamily: mono,
        fontSize: 12,
        height: 1.62,
        fontWeight: FontWeight.w400,
        color: Pal.text,
      );

  static TextStyle get button => TextStyle(
        fontFamily: ui,
        fontSize: 14.5,
        height: 1.1,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: Pal.onEmber,
      );
}

class Sp {
  const Sp._();
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const page = 20.0;
}

class Rd {
  const Rd._();
  static const sm = BorderRadius.all(Radius.circular(10));
  static const md = BorderRadius.all(Radius.circular(14));
  static const lg = BorderRadius.all(Radius.circular(18));
  static const xl = BorderRadius.all(Radius.circular(24));
  static const pill = BorderRadius.all(Radius.circular(999));
}

class Motion {
  const Motion._();
  static const fast = Duration(milliseconds: 110);
  static const base = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 320);
  static const ease = Curves.easeOutCubic;
  static const settle = Curves.easeOutQuart;
}
