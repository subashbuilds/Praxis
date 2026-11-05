import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

class PraxisApp extends StatefulWidget {
  const PraxisApp({super.key, required this.state});

  final AppState state;

  @override
  State<PraxisApp> createState() => _PraxisAppState();
}

class _PraxisAppState extends State<PraxisApp> {
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final dark = state.darkMode;
    Pal.use(dark ? Brightness.dark : Brightness.light);
    final iconBrightness = dark ? Brightness.light : Brightness.dark;
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Pal.canvas,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarDividerColor: Pal.canvas,
    );

    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Praxis',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(dark: dark),
        scrollBehavior: const _FlatScrollBehavior(),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
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
