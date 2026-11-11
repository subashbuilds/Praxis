import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/confirm_dialog.dart';

class PraxisApp extends StatefulWidget {
  const PraxisApp({super.key, required this.state});

  final AppState state;

  @override
  State<PraxisApp> createState() => _PraxisAppState();
}

class _PraxisAppState extends State<PraxisApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    _bindAgentPrompts();
  }

  /// Agent approvals belong to the app, not to one tab. Keeping them here lets
  /// a run continue and ask for permission after its project is closed.
  void _bindAgentPrompts() {
    final state = widget.state;
    state.limitPrompt = (title, body, accept) async {
      final context = _navigatorKey.currentContext;
      if (context == null) return false;
      return showPraxisConfirm(
        context,
        title: title,
        body: body,
        confirmLabel: accept,
        cancelLabel: 'Stop',
        icon: Icons.bolt_outlined,
      );
    };
    state.confirmPrompt = (title, body, accept) async {
      final context = _navigatorKey.currentContext;
      if (context == null) return false;
      final pull = title.toLowerCase().contains('pull');
      return showPraxisConfirm(
        context,
        title: title,
        body: body,
        confirmLabel: accept,
        icon:
            pull ? Icons.cloud_download_outlined : Icons.cloud_upload_outlined,
        note: 'The agent pauses here for your approval. Nothing leaves the '
            'device until you confirm.',
      );
    };
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
        navigatorKey: _navigatorKey,
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
