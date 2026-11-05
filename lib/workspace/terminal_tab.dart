import 'package:flutter/material.dart';

import '../core/shell.dart';
import '../models.dart';
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
  final _scroll = ScrollController();
  final _stdout = StringBuffer();
  final _stderr = StringBuffer();
  final _lines = <ShellLine>[
    const ShellLine(
      'Device shell — /system/bin/sh, working inside this project.',
      ShellTone.muted,
    ),
    const ShellLine(
      'git, curl or any binary installed on the phone is available. '
      'cd is tracked; clear empties this view.',
      ShellTone.muted,
    ),
  ];
  bool _running = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _feed(String chunk, ShellTone tone, StringBuffer pending) {
    if (!mounted) return;
    pending.write(chunk.replaceAll('\r', ''));
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
    if (command == 'clear') {
      setState(_lines.clear);
      return;
    }
    final shell = AppScope.of(context).systemShellFor(widget.project);
    _stdout.clear();
    _stderr.clear();
    setState(() {
      _running = true;
      _lines.add(ShellLine('\$ $command', ShellTone.command));
    });
    _scrollToEnd();

    final result = await shell.run(
      command,
      onStdout: (chunk) => _feed(chunk, ShellTone.output, _stdout),
      onStderr: (chunk) => _feed(chunk, ShellTone.error, _stderr),
    );
    if (!mounted) return;
    _flush(_stdout, ShellTone.output);
    _flush(_stderr, ShellTone.error);
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

  Color _tone(ShellTone tone) => switch (tone) {
        ShellTone.command => Pal.text,
        ShellTone.output => Pal.textMuted,
        ShellTone.muted => Pal.textDim,
        ShellTone.error => Pal.rose,
        ShellTone.accent => Pal.mint,
      };

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).systemShellFor(widget.project);

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
                StatusPill('device sh', color: Pal.mint),
                const SizedBox(width: Sp.x2),
                Expanded(
                  child: Text(
                    shell.cwdDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.meta.copyWith(fontSize: 10.5),
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
                    onTap: () => setState(_lines.clear),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x3),
              itemCount: _lines.length + (_running ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _lines.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '…',
                      style: Txt.code.copyWith(color: Pal.textDim),
                    ),
                  );
                }
                final line = _lines[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
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
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Pal.line)),
            ),
            padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x1, Sp.x2, Sp.x2),
            child: Row(
              children: [
                Text(
                  '\$',
                  style: Txt.code.copyWith(
                    fontSize: 12,
                    color: Pal.ember,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: Sp.x2),
                Expanded(
                  child: TextField(
                    controller: _input,
                    style: Txt.code.copyWith(fontSize: 11.5),
                    cursorColor: Pal.ember,
                    textInputAction: TextInputAction.send,
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !_running,
                    onSubmitted: _submit,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      hintText: 'git status',
                      hintStyle:
                          Txt.code.copyWith(fontSize: 11.5, color: Pal.textDim),
                    ),
                  ),
                ),
                IconAction(
                  icon: Icons.keyboard_return_rounded,
                  tooltip: 'Run command',
                  size: 18,
                  color: Pal.ember,
                  onTap: _running ? null : () => _submit(_input.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
