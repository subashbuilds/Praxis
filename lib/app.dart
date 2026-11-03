import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

class DevNestApp extends StatelessWidget {
  const DevNestApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'DevNest',
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
