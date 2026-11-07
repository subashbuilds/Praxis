import 'package:flutter/material.dart';

import '../core/file_types.dart';
import '../core/project_skills.dart';
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
    const ShellLine(
      'Python, Node, npm and git are not bundled with Praxis. A full package '
      'manager needs a native runtime or Termux bridge, which this build does '
      'not include.',
      ShellTone.muted,
    ),
  ];
  bool _running = false;
  bool _loadedSkills = false;
  List<ProjectSkill> _skills = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedSkills) return;
    _loadedSkills = true;
    _refreshSkills();
  }

  Future<void> _refreshSkills() async {
    final skills =
        await AppScope.of(context).installedSkillsFor(widget.project);
    if (mounted) setState(() => _skills = skills);
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
              Container(
                padding: const EdgeInsets.all(Sp.x3),
                decoration: BoxDecoration(
                  color: Pal.raised,
                  borderRadius: Rd.sm,
                  border: Border.all(color: Pal.line),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 16, color: Pal.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '.praxis/skills/  ·  ${_skills.length} installed',
                        style: Txt.code.copyWith(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Sp.x3),
              if (_skills.isEmpty)
                Text(
                  'No skills yet. Ask the agent to install one from a GitHub '
                  'repository or paste a SKILL.md, and it appears here.',
                  style: Txt.meta.copyWith(height: 1.5),
                )
              else
                for (final skill in _skills) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(Sp.x3),
                    decoration: BoxDecoration(
                      color: Pal.surface,
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
                            Text(
                              humanFileSize(skill.size),
                              style: Txt.meta.copyWith(fontSize: 9),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          skill.folder,
                          style: Txt.code
                              .copyWith(fontSize: 9.5, color: Pal.textDim),
                        ),
                        if (skill.description.isNotEmpty) ...[
                          const SizedBox(height: 5),
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
            ],
          ),
        ),
      ),
    );
  }

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
      _lines.add(
          ShellLine('${shell.promptDisplay} \$ $command', ShellTone.command));
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
                        Text(
                          '${_skills.length}',
                          style: Txt.meta.copyWith(fontSize: 9.5),
                        ),
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
                    onTap: () => setState(_lines.clear),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SelectionArea(
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
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Pal.line)),
            ),
            padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x1, Sp.x2, Sp.x2),
            child: Row(
              children: [
                Text(
                  shell.promptDisplay,
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
