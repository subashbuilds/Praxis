import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/chat.dart';
import '../models/project.dart';
import '../models/provider.dart';

enum TerminalTone { command, output, muted, error, accent }

class TerminalLine {
  const TerminalLine(this.text, [this.tone = TerminalTone.output]);
  final String text;
  final TerminalTone tone;
}

class AppState extends ChangeNotifier {
  AppState.seeded() {
    projects.addAll(_seedProjects);
    threads['polydev-web'] = _seedThread();
    terminal.addAll(_seedTerminal);
    files.addAll(_seedFiles);
  }

  final List<Project> projects = [];
  final Map<String, List<ChatItem>> threads = {};
  final List<TerminalLine> terminal = [];
  final Map<String, String> files = {};

  AiProvider provider = kProviders.first;
  bool usageStats = true;
  bool pushNews = true;
  bool wordWrap = false;
  bool agentBusy = false;
  int codeScale = 1;
  int devicesUsed = 2;
  int devicesMax = 3;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Project projectById(String id) =>
      projects.firstWhere((p) => p.id == id, orElse: () => projects.first);

  List<ChatItem> threadOf(String id) => threads.putIfAbsent(
        id,
        () => <ChatItem>[
          const AgentNote(
            'This project is ready. Ask me to build a screen, run a command, '
            'or wire up a deploy.',
          ),
        ],
      );

  void setProvider(AiProvider next) {
    provider = next;
    _notify();
  }

  void setUsageStats(bool value) {
    usageStats = value;
    _notify();
  }

  void setPushNews(bool value) {
    pushNews = value;
    _notify();
  }

  void setWordWrap(bool value) {
    wordWrap = value;
    _notify();
  }

  void setCodeScale(int value) {
    codeScale = value.clamp(0, 2);
    _notify();
  }

  Project createProject(String name, ProjectKind kind) {
    final trimmed = name.trim();
    final slug = trimmed
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-+|-+\$'), '');
    final project = Project(
      id: 'p-${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      path: '~/projects/${slug.isEmpty ? 'untitled' : slug}',
      branch: 'main',
      kind: kind,
      updated: 'just now',
    );
    projects.insert(0, project);
    threads[project.id] = <ChatItem>[
      AgentNote(
        'Scaffolded ${project.path} (${kind.label}). The Alpine rootfs is '
        'mounted and the shell is ready.',
      ),
    ];
    _notify();
    return project;
  }

  void sendPrompt(String projectId, String text) {
    final prompt = text.trim();
    if (prompt.isEmpty || agentBusy) return;

    final thread = threadOf(projectId);
    thread.add(UserNote(prompt));
    agentBusy = true;
    _notify();

    Timer(const Duration(milliseconds: 750), () {
      if (_disposed) return;
      thread.add(const AgentNote(
          'Reading the project and planning the smallest diff…'));
      _notify();

      Timer(const Duration(milliseconds: 1050), () {
        if (_disposed) return;
        thread.add(const CommandRun(
          command: 'rg "ThemeMode" lib',
          output: 'lib/app.dart:23  themeMode: ThemeMode.dark,\n'
              'lib/theme/app_theme.dart:9  ThemeData buildAppTheme()',
        ));
        thread.add(const FileEdit(
          path: 'lib/app.dart',
          added: 6,
          removed: 2,
          diff: [
            ' ThemeData buildAppTheme() {',
            '-  final scheme = ColorScheme.dark();',
            '+  final scheme = ColorScheme.dark(',
            '+    primary: Pal.ember,',
            '+    onPrimary: Pal.onEmber,',
            '+  );',
          ],
        ));
        thread.add(const AgentNote(
          'Done. The ember primary is applied and the analyzer is clean. '
          'Run it to check the composer contrast on a real device.',
        ));
        agentBusy = false;
        _notify();
      });
    });
  }

  void runCommand(String raw) {
    final cmd = raw.trim();
    if (cmd.isEmpty) return;

    terminal.add(TerminalLine('~ \$ $cmd', TerminalTone.command));

    if (cmd == 'clear') {
      terminal.clear();
      _notify();
      return;
    }

    void out(String text, [TerminalTone tone = TerminalTone.output]) {
      terminal.add(TerminalLine(text, tone));
    }

    if (cmd == 'ls') {
      out('app   assets   lib   pubspec.yaml   README.md');
    } else if (cmd == 'pwd') {
      out('/data/user/0/com.xapi.polydev/files/home/projects/polydev-web');
    } else if (cmd == 'whoami') {
      out('root  ·  proot  ·  Alpine 3.21.7 aarch64', TerminalTone.muted);
    } else if (cmd.startsWith('node -v')) {
      out('v22.9.0');
    } else if (cmd.startsWith('flutter --version')) {
      out('Flutter 3.24.5 • channel stable • Dart 3.5.4', TerminalTone.accent);
    } else if (cmd.startsWith('flutter analyze')) {
      out('Analyzing polydev-web…', TerminalTone.muted);
      out('No issues found! (ran in 2.4s)', TerminalTone.accent);
    } else if (cmd.startsWith('npm run dev') || cmd.startsWith('npm i')) {
      out('');
      out('  VITE v5.4.2  ready in 412 ms', TerminalTone.accent);
      out('  ➜  Local:   http://localhost:5173/');
      out('  ➜  press h + enter to show help', TerminalTone.muted);
    } else if (cmd.startsWith('git status')) {
      out('On branch main', TerminalTone.muted);
      out('Changes not staged for commit:', TerminalTone.muted);
      out('  modified:   lib/app.dart');
      out('  modified:   lib/theme/app_theme.dart');
    } else if (cmd.startsWith('git ')) {
      out('On branch main · up to date with origin/main', TerminalTone.muted);
    } else if (cmd == 'help') {
      out('Try: ls · pwd · node -v · flutter analyze · npm run dev · git status · clear',
          TerminalTone.muted);
    } else {
      out('zsh: command not found: $cmd', TerminalTone.error);
    }
    _notify();
  }

  void clearLocalData() {
    terminal.clear();
    threads.clear();
    threads['polydev-web'] = _seedThread();
    _notify();
  }

  static const List<Project> _seedProjects = [
    Project(
      id: 'polydev-web',
      name: 'polydev-web',
      path: '~/projects/polydev-web',
      branch: 'main',
      kind: ProjectKind.flutter,
      updated: '2h ago',
      running: true,
    ),
    Project(
      id: 'ember-dashboard',
      name: 'ember-dashboard',
      path: '~/projects/ember-dashboard',
      branch: 'feat/charts',
      kind: ProjectKind.node,
      updated: 'yesterday',
    ),
    Project(
      id: 'alpine-notes',
      name: 'alpine-notes',
      path: '~/projects/alpine-notes',
      branch: 'main',
      kind: ProjectKind.python,
      updated: '3d ago',
    ),
  ];

  static List<ChatItem> _seedThread() => const [
        UserNote(
            'The composer sits under the keyboard on small screens. Fix it and keep the ember accent.'),
        AgentNote(
            'Checking how the shell handles insets before touching layout.'),
        CommandRun(
          command: 'rg -n "viewInsets|SafeArea" lib',
          output: 'lib/app.dart:41  return SafeArea(top: false, child: …);\n'
              'lib/workspace/composer.dart:18  padding: EdgeInsets.only(bottom: 12),',
        ),
        FileEdit(
          path: 'lib/workspace/composer.dart',
          added: 4,
          removed: 3,
          diff: [
            ' Widget build(BuildContext context) {',
            '-  return Padding(',
            '-    padding: const EdgeInsets.only(bottom: 12),',
            '+  final inset = MediaQuery.viewInsetsOf(context).bottom;',
            '+  return Padding(',
            '+    padding: EdgeInsets.only(bottom: inset + 12),',
          ],
        ),
        AgentNote(
          'The composer now tracks viewInsets and keeps a 12dp gap above the '
          'keyboard. Analyzer is clean — want me to run it on device?',
        ),
      ];

  static const List<TerminalLine> _seedTerminal = [
    TerminalLine('cat /etc/os-release | head -2', TerminalTone.command),
    TerminalLine('NAME="Alpine Linux"', TerminalTone.muted),
    TerminalLine('VERSION_ID=3.21.7', TerminalTone.muted),
    TerminalLine('node -v', TerminalTone.command),
    TerminalLine('v22.9.0'),
    TerminalLine('npm run dev', TerminalTone.command),
    TerminalLine('  VITE v5.4.2  ready in 412 ms', TerminalTone.accent),
    TerminalLine('  ➜  Local:   http://localhost:5173/'),
    TerminalLine('  ➜  Network: use --host to expose', TerminalTone.muted),
  ];

  static const Map<String, String> _seedFiles = {
    'pubspec.yaml': r'''name: polydev
description: On-device AI coding agent.
version: 1.0.0+13

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_svg: ^2.0.10
''',
    'lib/main.dart': r'''import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PolyDevApp());
}
''',
    'lib/app.dart': r'''import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'PolyDev',
        theme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        home: const HomeScreen(),
      ),
    );
  }
}
''',
    'lib/theme/tokens.dart': r'''import 'package:flutter/material.dart';

class Pal {
  static const canvas = Color(0xFF0A0908);
  static const surface = Color(0xFF12100E);
  static const raised = Color(0xFF1A1714);
  static const ember = Color(0xFFE4693F);
  static const onEmber = Color(0xFF1A0E08);
}
''',
    'lib/workspace/composer.dart': r'''import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';

class Composer extends StatelessWidget {
  const Composer({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset + 12),
      child: const _Field(),
    );
  }
}
''',
    'README.md': r'''# polydev-web

Rebuilt interface for the PolyDev on-device agent.

- Agent, terminal and preview in one shell
- Alpine rootfs mounted through proot
- Deploys to Vercel and Cloudflare Pages
''',
  };
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }
}
