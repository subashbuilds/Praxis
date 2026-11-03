import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class AgentTab extends StatefulWidget {
  const AgentTab({super.key, required this.project});

  final Project project;

  @override
  State<AgentTab> createState() => _AgentTabState();
}

class _AgentTabState extends State<AgentTab> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Motion.base,
        curve: Motion.ease,
      );
    });
  }

  Future<void> _send() async {
    final text = _composer.text;
    if (text.trim().isEmpty) return;
    _composer.clear();
    _scrollToEnd();
    await AppScope.of(context).send(widget.project.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final thread = state.threadOf(widget.project.id);
    if (thread.length != _lastCount) {
      _lastCount = thread.length;
      _scrollToEnd();
    }

    return Column(
      children: [
        Expanded(
          child: thread.isEmpty
              ? _EmptyAgent(onPrompt: (value) {
                  _composer.text = value;
                  _send();
                })
              : ListView.builder(
                  controller: _scroll,
                  padding:
                      const EdgeInsets.fromLTRB(Sp.page, Sp.x4, Sp.page, Sp.x4),
                  itemCount: thread.length,
                  itemBuilder: (context, index) =>
                      _EntryView(entry: thread[index]),
                ),
        ),
        _Composer(
          controller: _composer,
          busy: state.busy,
          onSend: _send,
          onStop: state.stop,
          onClear:
              thread.isEmpty ? null : () => state.clearChat(widget.project.id),
        ),
      ],
    );
  }
}

class _EmptyAgent extends StatelessWidget {
  const _EmptyAgent({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    const suggestions = [
      'Make the landing page look sharper',
      'Add a dark mode toggle to app.js',
      'List the files and explain them',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x6, Sp.page, Sp.x4),
      children: [
        const Text('Ask for a change.', style: Txt.headline),
        const SizedBox(height: 8),
        const Text(
          'The agent reads and writes real files in this project. Every tool '
          'call is shown below the reply, so you can check what changed.',
          style: Txt.bodySoft,
        ),
        const SizedBox(height: Sp.x5),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onPrompt(suggestion),
              behavior: HitTestBehavior.opaque,
              child: Panel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_outward_rounded,
                        size: 15, color: Pal.ember),
                    const SizedBox(width: 9),
                    Expanded(child: Text(suggestion, style: Txt.bodySoft)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EntryView extends StatelessWidget {
  const _EntryView({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    switch (entry.role) {
      case ChatRole.user:
        return Padding(
          padding: const EdgeInsets.only(bottom: Sp.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('YOU', style: Txt.overline.copyWith(color: Pal.textDim)),
              const SizedBox(height: 5),
              Text(entry.text, style: Txt.body.copyWith(fontSize: 14.5)),
            ],
          ),
        );
      case ChatRole.assistant:
        return Padding(
          padding: const EdgeInsets.only(bottom: Sp.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BrandMark(size: 12),
                  const SizedBox(width: 6),
                  Text(
                    'DEVNEST',
                    style: Txt.overline.copyWith(color: Pal.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(entry.text, style: Txt.body.copyWith(height: 1.55)),
            ],
          ),
        );
      case ChatRole.tool:
        return _ToolCard(entry: entry);
      case ChatRole.error:
        return Padding(
          padding: const EdgeInsets.only(bottom: Sp.x4),
          child: Panel(
            borderColor: Pal.rose.withOpacity(0.45),
            padding: const EdgeInsets.all(Sp.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 17, color: Pal.rose),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    entry.text,
                    style: Txt.bodySoft.copyWith(color: Pal.rose),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.entry});

  final ChatEntry entry;

  IconData get _icon => switch (entry.tool) {
        'write_file' => Icons.edit_note_rounded,
        'read_file' => Icons.description_outlined,
        'run_command' => Icons.terminal_rounded,
        'list_files' => Icons.folder_open_rounded,
        _ => Icons.build_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final failed = entry.text.toLowerCase().startsWith('error');
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x3),
      child: Panel(
        padding: const EdgeInsets.all(Sp.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon, size: 15, color: failed ? Pal.rose : Pal.mint),
                const SizedBox(width: 7),
                Text(
                  entry.tool,
                  style: Txt.meta.copyWith(
                    color: failed ? Pal.rose : Pal.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    entry.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.meta.copyWith(fontSize: 10),
                  ),
                ),
              ],
            ),
            if (entry.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Pal.terminal,
                  borderRadius: Rd.sm,
                  border: Border.all(color: Pal.line),
                ),
                child: Text(
                  entry.text.trim(),
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.code.copyWith(
                    fontSize: 10.5,
                    height: 1.5,
                    color: Pal.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onStop,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Pal.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        Sp.x3,
        Sp.x2,
        Sp.x3,
        Sp.x2 + MediaQuery.paddingOf(context).bottom.clamp(0, 0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconAction(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Clear chat',
            size: 18,
            onTap: onClear,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: Txt.body,
              cursorColor: Pal.ember,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: appField(
                busy ? 'Working…' : 'Ask for a change',
              ),
              onSubmitted: busy ? null : (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: busy ? onStop : onSend,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: busy ? Pal.rose : Pal.ember,
                borderRadius: Rd.sm,
              ),
              child: Icon(
                busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                size: 20,
                color: Pal.onEmber,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
