import 'package:flutter/material.dart';

/// DevNest palette: ember on warm graphite, dark-first by design. Machine
/// output gets its own near-black well so code never shares a surface with UI.
class Pal {
  const Pal._();

  static const canvas = Color(0xFF0A0908);
  static const surface = Color(0xFF12100E);
  static const raised = Color(0xFF1A1714);
  static const overlay = Color(0xFF241F1B);

  static const line = Color(0xFF2C2621);
  static const lineStrong = Color(0xFF3B342D);

  static const text = Color(0xFFF4EFE9);
  static const textMuted = Color(0xFFB7ADA2);
  static const textDim = Color(0xFF877E74);

  static const ember = Color(0xFFE4693F);
  static const emberDeep = Color(0xFFB94723);
  static const onEmber = Color(0xFF1A0E08);

  static const mint = Color(0xFF7FD1A8);
  static const amber = Color(0xFFE8B45C);
  static const rose = Color(0xFFF07A6E);
  static const sky = Color(0xFF8AB4F0);

  /// Terminal well is a touch darker than the canvas so code reads as
  /// a separate material.
  static const terminal = Color(0xFF070706);

  /// GitHub's dark code palette, used by the editor and the diff pills so
  /// added and removed lines read the same way they do on GitHub.
  static const ghBg = Color(0xFF0D1117);
  static const ghPanel = Color(0xFF161B22);
  static const ghLine = Color(0xFF30363D);
  static const ghText = Color(0xFFE6EDF3);
  static const ghMuted = Color(0xFF8B949E);
  static const ghKeyword = Color(0xFFFF7B72);
  static const ghString = Color(0xFFA5D6FF);
  static const ghNumber = Color(0xFF79C0FF);
  static const ghTag = Color(0xFF7EE787);
  static const ghAttr = Color(0xFFD2A8FF);
  static const ghAddBg = Color(0xFF12261E);
  static const ghAddText = Color(0xFF7EE787);
  static const ghDelBg = Color(0xFF2D1417);
  static const ghDelText = Color(0xFFFFA198);
}

/// Type roles. Inter for interface, JetBrains Mono for anything the
/// machine produced, Lora for the two editorial moments in the app.
class Txt {
  const Txt._();

  static const ui = 'Inter';
  static const mono = 'JetBrainsMono';
  static const serif = 'Lora';

  static const display = TextStyle(
    fontFamily: serif,
    fontSize: 30,
    height: 1.14,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    color: Pal.text,
  );

  static const headline = TextStyle(
    fontFamily: ui,
    fontSize: 25,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    color: Pal.text,
  );

  static const title = TextStyle(
    fontFamily: ui,
    fontSize: 16.5,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: Pal.text,
  );

  static const body = TextStyle(
    fontFamily: ui,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: Pal.text,
  );

  static const bodySoft = TextStyle(
    fontFamily: ui,
    fontSize: 13.5,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: Pal.textMuted,
  );

  static const label = TextStyle(
    fontFamily: ui,
    fontSize: 12.5,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: Pal.textMuted,
  );

  static const meta = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: Pal.textDim,
    letterSpacing: 0.1,
  );

  static const overline = TextStyle(
    fontFamily: mono,
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: Pal.textDim,
  );

  static const code = TextStyle(
    fontFamily: mono,
    fontSize: 12,
    height: 1.62,
    fontWeight: FontWeight.w400,
    color: Pal.text,
  );

  static const button = TextStyle(
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
