import 'dart:async';

import 'package:flutter/material.dart';

import '../core/file_types.dart';
import '../core/linux_environment.dart';
import '../core/project_skills.dart';
import '../core/shell.dart';
import '../core/system_shell.dart';
import '../models.dart';
import '../screens/linux_environment_screen.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class TerminalTab extends StatefulWidget {
  const TerminalTab({super.key, required this.project});

  final Project project;

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _pendingOut = StringBuffer();
  final _pendingErr = StringBuffer();
  final _lines = <ShellLine>[];
  final _history = <String>[];
  final _skills = <ProjectSkill>[];
  bool _running = false;
  bool _started = false;
  bool _loadedSkills = false;
  int _historyIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!_started) {
      _started = true;
      final linux = state.linux;
      _lines.addAll(_welcome(linux));
      if (linux != null) unawaited(linux.prepare());
    }
    if (!_loadedSkills) {
      _loadedSkills = true;
      unawaited(_refreshSkills());
    }
  }

  List<ShellLine> _welcome(LinuxEnvironment? linux) {
    if (linux == null) {
      return const [
        ShellLine(
          'Praxis shell',
          ShellTone.accent,
        ),
        ShellLine(
          'A shell is available in the Android build.',
          ShellTone.muted,
        ),
      ];
    }
    return const [
      ShellLine('Praxis · Alpine Linux 3.21.7', ShellTone.accent),
      ShellLine(
        'A real Alpine rootfs under proot. You are root; the project is /workspace.',
        ShellTone.output,
      ),
      ShellLine('', ShellTone.output),
      ShellLine('Install packages with apk:', ShellTone.muted),
      ShellLine('  apk add nodejs npm', ShellTone.command),
      ShellLine('  apk add python3 py3-pip', ShellTone.command),
      ShellLine('  apk add git', ShellTone.command),
      ShellLine('  apk --help', ShellTone.command),
      ShellLine(
        'apt and apt-get do not exist here. Type clear to reset this view.',
        ShellTone.muted,
      ),
      ShellLine('', ShellTone.output),
    ];
  }

  Future<void> _refreshSkills() async {
    final skills =
        await AppScope.of(context).installedSkillsFor(widget.project);
    if (mounted) {
      setState(() {
        _skills
          ..clear()
          ..addAll(skills);
      });
    }
  }

  Future<void> _showSkills() async {
    await _refreshSkills();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (_, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x5),
            children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: Sp.x3),
              Text('Project skills',
                  style: Txt.headline.copyWith(fontSize: 21)),
              const SizedBox(height: 4),
              Text(
                'Installed in .praxis/skills. Every folder holds a SKILL.md and '
                'loads into the next agent turn for this project.',
                style: Txt.bodySoft.copyWith(height: 1.5),
              ),
              const SizedBox(height: Sp.x3),
              if (_skills.isEmpty)
                Text(
                  'No skills yet. Ask the agent to install one.',
                  style: Txt.meta.copyWith(height: 1.5),
                )
              else
                for (final skill in _skills)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(Sp.x3),
                    decoration: BoxDecoration(
                      color: Pal.raised,
                      borderRadius: Rd.sm,
                      border: Border.all(color: Pal.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.extension_outlined,
                                size: 16, color: Pal.mint),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(skill.name,
                                  style: Txt.label.copyWith(fontSize: 12)),
                            ),
                            Text(humanFileSize(skill.size),
                                style: Txt.meta.copyWith(fontSize: 9)),
                          ],
                        ),
                        if (skill.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            skill.description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Txt.meta.copyWith(height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _feed(String chunk, ShellTone tone, StringBuffer pending) {
    if (!mounted) return;
    final clean = chunk
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    pending.write(clean);
    final parts = pending.toString().split('\n');
    pending.clear();
    pending.write(parts.removeLast());
    if (parts.isEmpty) return;
    setState(() {
      _lines.addAll(parts.map((line) => ShellLine(line, tone)));
    });
    _scrollToEnd();
  }

  void _flush(StringBuffer pending, ShellTone tone) {
    final rest = pending.toString();
    pending.clear();
    if (rest.isEmpty) return;
    setState(() => _lines.add(ShellLine(rest, tone)));
  }

  Future<void> _submit(String raw) async {
    final command = raw.trim();
    if (command.isEmpty || _running) return;
    _input.clear();
    _focus.requestFocus();
    if (command == 'clear') {
      setState(() {
        _lines
          ..clear()
          ..addAll(_welcome(AppScope.of(context).linux));
      });
      _scrollToEnd();
      return;
    }
    if (_history.isEmpty || _history.last != command) {
      _history.add(command);
    }
    _historyIndex = _history.length;
    final state = AppScope.of(context);
    final shell = state.systemShellFor(widget.project);
    final linux = state.linux;
    final prompt =
        linux == null ? shell.promptDisplay : 'alpine:${shell.promptDisplay}';
    _pendingOut.clear();
    _pendingErr.clear();
    setState(() {
      _running = true;
      _lines.add(ShellLine('$prompt \$ $command', ShellTone.command));
    });
    _scrollToEnd();

    final result = await shell.run(
      command,
      onStdout: (chunk) => _feed(chunk, ShellTone.output, _pendingOut),
      onStderr: (chunk) => _feed(chunk, ShellTone.error, _pendingErr),
    );
    if (!mounted) return;
    _flush(_pendingOut, ShellTone.output);
    _flush(_pendingErr, ShellTone.error);
    setState(() {
      _running = false;
      if (result.exitCode != 0) {
        _lines.add(ShellLine('exit ${result.exitCode}', ShellTone.muted));
      }
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _openLinux() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LinuxEnvironmentScreen(project: widget.project),
      ),
    );
  }

  String _displayCwd(SystemShell shell, LinuxEnvironment? linux) {
    if (linux == null) return shell.cwdDisplay;
    return shell.cwd.isEmpty
        ? '/workspace'
        : '/workspace/${shell.cwd.replaceAll(RegExp(r'/+$'), '')}';
  }

  String _resources(LinuxEnvironment? linux) {
    if (linux == null || !linux.ready) return '';
    final load = linux.snapshot.load1;
    final ram = linux.snapshot.ramUsedBytes;
    final cpu = load == null ? '—' : load.toStringAsFixed(2);
    final memory = ram == null ? '—' : humanBytes(ram);
    return 'CPU $cpu · RAM $memory';
  }

  Color _tone(ShellTone tone) => switch (tone) {
        ShellTone.command => Pal.text,
        ShellTone.output => Pal.textMuted,
        ShellTone.muted => Pal.textDim,
        ShellTone.error => Pal.rose,
        ShellTone.accent => Pal.mint,
      };

  void _insert(String value) {
    final selection = _input.selection;
    final start = selection.isValid ? selection.start : _input.text.length;
    final end = selection.isValid ? selection.end : _input.text.length;
    final text = _input.text.replaceRange(start, end, value);
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    _focus.requestFocus();
  }

  void _moveCursor(int delta) {
    final selection = _input.selection;
    final base = selection.isValid ? selection.end : _input.text.length;
    final offset = (base + delta).clamp(0, _input.text.length);
    _input.selection = TextSelection.collapsed(offset: offset);
    _focus.requestFocus();
  }

  void _historyMove(int delta) {
    if (_history.isEmpty) return;
    final next = (_historyIndex + delta).clamp(0, _history.length);
    if (next == _history.length) {
      _input.clear();
    } else {
      _input.text = _history[next];
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    _historyIndex = next;
    _focus.requestFocus();
  }

  void _showCtrlMenu() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            ListTile(
              leading: Icon(Icons.stop_circle_outlined, color: Pal.rose),
              title: const Text('Ctrl + C · interrupt'),
              onTap: () {
                AppScope.of(context).systemShellFor(widget.project).cancel();
                Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              leading: Icon(Icons.cleaning_services_outlined, color: Pal.amber),
              title: const Text('Ctrl + L · clear screen'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() {
                  _lines
                    ..clear()
                    ..addAll(_welcome(AppScope.of(context).linux));
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.keyboard_hide_rounded, color: Pal.textMuted),
              title: const Text('Ctrl + D · close keyboard'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _focus.unfocus();
              },
            ),
            const SizedBox(height: Sp.x2),
          ],
        ),
      ),
    );
  }

  Widget _promptRow() {
    final shell = AppScope.of(context).systemShellFor(widget.project);
    final linux = AppScope.of(context).linux;
    final prompt =
        linux == null ? shell.promptDisplay : 'alpine:${shell.promptDisplay}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '\$ ',
              style: Txt.code.copyWith(
                fontSize: 12,
                color: Pal.ember,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              style: Txt.code.copyWith(fontSize: 11.5),
              cursorColor: Pal.ember,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.send,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: _submit,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: '$prompt \$ ',
                hintStyle:
                    Txt.code.copyWith(fontSize: 11.5, color: Pal.textDim),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final shell = state.systemShellFor(widget.project);
    final linux = state.linux;
    final ready = linux?.ready ?? false;
    final linuxFailed = linux?.state == LinuxState.error;
    return Container(
      color: Pal.terminal,
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.fromLTRB(Sp.x4, Sp.x2 + 2, Sp.x2, Sp.x2 + 2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Pal.line)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: linux == null ? null : _openLinux,
                  behavior: HitTestBehavior.opaque,
                  child: StatusPill(
                    linux == null
                        ? 'device sh'
                        : ready
                            ? 'alpine'
                            : linuxFailed
                                ? 'unavailable'
                                : 'preparing',
                    color: ready
                        ? Pal.mint
                        : linuxFailed
                            ? Pal.rose
                            : Pal.amber,
                  ),
                ),
                const SizedBox(width: Sp.x2),
                Expanded(
                  child: Text(
                    _displayCwd(shell, linux),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.meta.copyWith(fontSize: 10.5),
                  ),
                ),
                if (linux != null && ready)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Text(
                      _resources(linux),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.meta.copyWith(
                        fontSize: 8.5,
                        color: Pal.textDim,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: _showSkills,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: Pal.raised,
                      borderRadius: Rd.pill,
                      border: Border.all(color: Pal.line),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.extension_outlined,
                            size: 12, color: Pal.amber),
                        const SizedBox(width: 4),
                        Text('${_skills.length}',
                            style: Txt.meta.copyWith(fontSize: 9.5)),
                      ],
                    ),
                  ),
                ),
                if (_running)
                  IconAction(
                    icon: Icons.stop_circle_outlined,
                    tooltip: 'Stop command',
                    size: 18,
                    color: Pal.rose,
                    onTap: shell.cancel,
                  )
                else
                  IconAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Clear shell',
                    size: 17,
                    onTap: () => setState(() {
                      _lines
                        ..clear()
                        ..addAll(_welcome(linux));
                    }),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _focus.requestFocus,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: Sp.x2),
                itemCount: _lines.length + 1,
                itemBuilder: (context, index) {
                  if (index == _lines.length) return _promptRow();
                  final line = _lines[index];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(Sp.x4, 1.5, Sp.x4, 1.5),
                    child: Text(
                      line.text.isEmpty ? ' ' : line.text,
                      style: Txt.code.copyWith(
                        fontSize: 11.5,
                        height: 1.55,
                        color: _tone(line.tone),
                        fontWeight: line.tone == ShellTone.command
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          _symbolBar(),
          _specialBar(shell, linux),
        ],
      ),
    );
  }

  Widget _symbolBar() {
    const symbols = [
      '|',
      '~',
      '`',
      '/',
      r'$',
      '{',
      '}',
      '[',
      ']',
      '(',
      ')',
      '<',
      '>',
      ';',
      ':',
      "'",
      '"',
      '=',
      '+',
      '-',
      '*',
      '&',
      '!',
      '?',
      '#',
      '@',
      '%',
      '^',
      '_',
      '.',
      ',',
    ];
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Pal.surface,
        border: Border(top: BorderSide(color: Pal.line)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: Sp.x2, vertical: 5),
        scrollDirection: Axis.horizontal,
        itemCount: symbols.length,
        separatorBuilder: (_, __) => const SizedBox(width: 3),
        itemBuilder: (context, index) {
          final symbol = symbols[index];
          return GestureDetector(
            onTap: () => _insert(symbol),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Pal.raised,
                borderRadius: Rd.sm,
                border: Border.all(color: Pal.line),
              ),
              child: Text(
                symbol,
                style: Txt.code.copyWith(
                  fontSize: 15,
                  color: Pal.textMuted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _specialBar(SystemShell shell, LinuxEnvironment? linux) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(
        color: Pal.surface,
        border: Border(top: BorderSide(color: Pal.line)),
      ),
      child: Row(
        children: [
          _specialKey('ESC', Icons.keyboard_hide_rounded, () {
            shell.cancel();
            _focus.unfocus();
          }),
          _specialKey(
              'Ctrl', Icons.keyboard_command_key_rounded, _showCtrlMenu),
          const Spacer(),
          _specialKey(
              null, Icons.keyboard_arrow_left_rounded, () => _moveCursor(-1)),
          _specialKey(
              null, Icons.keyboard_arrow_up_rounded, () => _historyMove(-1)),
          _specialKey(
              null, Icons.keyboard_arrow_down_rounded, () => _historyMove(1)),
          _specialKey(
              null, Icons.keyboard_arrow_right_rounded, () => _moveCursor(1)),
          _specialKey(
            null,
            Icons.keyboard_return_rounded,
            () => _submit(_input.text),
            emphasized: true,
          ),
        ],
      ),
    );
  }

  Widget _specialKey(
    String? label,
    IconData icon,
    VoidCallback onTap, {
    bool emphasized = false,
  }) {
    return Semantics(
      button: true,
      label: label ?? 'Terminal key',
      child: InkWell(
        onTap: onTap,
        borderRadius: Rd.sm,
        child: SizedBox(
          width: label == null ? 42 : 52,
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: emphasized ? Pal.ember : Pal.textMuted,
              ),
              if (label != null) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: Txt.meta.copyWith(
                    fontSize: 9,
                    color: emphasized ? Pal.ember : Pal.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
