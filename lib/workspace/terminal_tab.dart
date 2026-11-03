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
  final _lines = <ShellLine>[
    const ShellLine(
        'DevNest shell — running against the project folder on this device.',
        ShellTone.muted),
    const ShellLine(
        "Type 'help' for the commands it understands.", ShellTone.muted),
  ];
  bool _running = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final command = raw.trim();
    if (command.isEmpty || _running) return;
    final shell = AppScope.of(context).shellFor(widget.project);
    _input.clear();
    setState(() {
      _running = true;
      _lines
          .add(ShellLine('${shell.cwdDisplay} \$ $command', ShellTone.command));
    });
    final result = await shell.run(command);
    if (!mounted) return;
    setState(() {
      _running = false;
      if (result.clear) {
        _lines.clear();
      } else {
        _lines.addAll(result.lines);
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
    final shell = AppScope.of(context).shellFor(widget.project);

    return Container(
      color: Pal.terminal,
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.fromLTRB(Sp.x4, Sp.x2 + 2, Sp.x2, Sp.x2 + 2),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Pal.line)),
            ),
            child: Row(
              children: [
                const StatusPill('local', color: Pal.mint),
                const SizedBox(width: Sp.x2),
                Expanded(
                  child: Text(
                    shell.cwdDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.meta.copyWith(fontSize: 10.5),
                  ),
                ),
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
                    child:
                        Text('…', style: Txt.code.copyWith(color: Pal.textDim)),
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
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Pal.line)),
            ),
            padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x1, Sp.x2, Sp.x2),
            child: Row(
              children: [
                Text(
                  '${shell.cwdDisplay} \$',
                  style: Txt.code.copyWith(
                    fontSize: 11.5,
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
                    onSubmitted: _submit,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      hintText: 'ls',
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
                  onTap: () => _submit(_input.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
