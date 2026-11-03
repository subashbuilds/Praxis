import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

class PolyDevApp extends StatefulWidget {
  const PolyDevApp({super.key});

  @override
  State<PolyDevApp> createState() => _PolyDevAppState();
}

class _PolyDevAppState extends State<PolyDevApp> {
  final AppState _state = AppState.seeded();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'PolyDev',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        scrollBehavior: const _FlatScrollBehavior(),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Pal.canvas,
            systemNavigationBarIconBrightness: Brightness.light,
            systemNavigationBarDividerColor: Pal.canvas,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

/// The shipped app has no Material overscroll glow; the interface is flat,
/// so the stretch/glow would read as chrome.
class _FlatScrollBehavior extends MaterialScrollBehavior {
  const _FlatScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
