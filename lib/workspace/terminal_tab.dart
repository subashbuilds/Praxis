import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

class TerminalTab extends StatefulWidget {
  const TerminalTab({super.key});

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final state = AppScope.of(context);
    if (value.trim().isEmpty) return;
    state.runCommand(value);
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Color _color(TerminalTone tone) => switch (tone) {
        TerminalTone.command => Pal.text,
        TerminalTone.output => Pal.textMuted,
        TerminalTone.muted => Pal.textDim,
        TerminalTone.error => Pal.rose,
        TerminalTone.accent => Pal.mint,
      };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

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
                const StatusPill('proot', color: Pal.mint),
                const SizedBox(width: Sp.x2),
                Expanded(
                  child: Text(
                    'alpine 3.21.7 · aarch64',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.meta.copyWith(fontSize: 10.5),
                  ),
                ),
                IconAction(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Clear shell',
                  size: 17,
                  onTap: () => state.runCommand('clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x4, Sp.x3),
              itemCount: state.terminal.length,
              itemBuilder: (context, i) {
                final line = state.terminal[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    line.text.isEmpty ? ' ' : line.text,
                    style: Txt.code.copyWith(
                      fontSize: 11.5,
                      height: 1.55,
                      color: _color(line.tone),
                      fontWeight: line.tone == TerminalTone.command
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
                  '~ \$',
                  style: Txt.code.copyWith(
                    fontSize: 11.5,
                    color: Pal.ember,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: Sp.x2),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
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
                      hintText: 'run a command',
                      hintStyle: Txt.code.copyWith(
                        fontSize: 11.5,
                        color: Pal.textDim,
                      ),
                    ),
                  ),
                ),
                IconAction(
                  icon: Icons.keyboard_return_rounded,
                  tooltip: 'Run command',
                  size: 18,
                  color: Pal.ember,
                  onTap: () => _submit(_controller.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
