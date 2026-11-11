import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/diff.dart';
import '../core/task_checkpoint.dart';
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
  final _attachments = <String>[];
  int _lastThreadLength = 0;
  int _lastLiveSignal = 0;
  bool _stickToBottom = true;
  bool _showJumpToBottom = false;
  bool _draftRestored = false;
  AppState? _state;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    _state = state;
    if (!_draftRestored) {
      _draftRestored = true;
      final draft = state.promptDraftFor(widget.project.id);
      _composer.text = draft;
      _composer.selection = TextSelection.collapsed(offset: draft.length);
      _composer.addListener(_persistDraft);
    }
  }

  @override
  void dispose() {
    _state?.setPromptDraft(widget.project.id, _composer.text);
    _composer.removeListener(_persistDraft);
    _composer.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _persistDraft() {
    _state?.setPromptDraft(widget.project.id, _composer.text);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearBottom =
        _scroll.position.maxScrollExtent - _scroll.position.pixels <= 80;
    if (nearBottom == _stickToBottom) return;
    setState(() {
      _stickToBottom = nearBottom;
      _showJumpToBottom = !nearBottom;
    });
  }

  void _scrollToEnd({bool force = false}) {
    if (!force && !_stickToBottom) return;
    if (force && !_stickToBottom) {
      setState(() {
        _stickToBottom = true;
        _showJumpToBottom = false;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _pickAttachments() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Pal.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            ListTile(
              leading: Icon(Icons.image_outlined, color: Pal.textMuted),
              title: const Text('Photos'),
              subtitle: const Text('Images from the gallery'),
              onTap: () => Navigator.of(sheetContext).pop('image'),
            ),
            ListTile(
              leading: Icon(Icons.attach_file_rounded, color: Pal.textMuted),
              title: const Text('Any file'),
              subtitle:
                  const Text('Text, PDF or zip — copied into the project'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: kind == 'image' ? FileType.image : FileType.any,
        allowMultiple: true,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the picker: $error')),
      );
      return;
    }
    if (!mounted) return;
    final paths = result?.files
            .map((file) => file.path)
            .whereType<String>()
            .where((path) => path.isNotEmpty)
            .toList() ??
        const <String>[];
    if (paths.isEmpty) return;
    setState(() => _attachments.addAll(paths));
  }

  Future<void> _send() async {
    final text = _composer.text;
    if ((text.trim().isEmpty && _attachments.isEmpty) || _state?.busy == true) {
      return;
    }
    final files = List<String>.from(_attachments);
    _composer.clear();
    _state?.setPromptDraft(widget.project.id, '');
    setState(_attachments.clear);
    _scrollToEnd(force: true);
    await AppScope.of(context)
        .send(widget.project.id, text, attachments: files);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final thread = state.threadOf(widget.project.id);
    final liveSignal = state.liveText.length +
        state.liveThinking.length +
        state.liveTools.length;
    if (thread.length != _lastThreadLength || liveSignal != _lastLiveSignal) {
      _lastThreadLength = thread.length;
      _lastLiveSignal = liveSignal;
      _scrollToEnd();
    }

    final showLive = state.busy || state.hasLiveReply;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: thread.isEmpty && !showLive
                    ? _EmptyAgent(
                        kind: widget.project.kind,
                        onPrompt: (value) {
                          _composer.text = value;
                          _send();
                        },
                      )
                    : SelectionArea(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(
                              Sp.x4, Sp.x4, Sp.x4, Sp.x2),
                          itemCount: thread.length + (showLive ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= thread.length) {
                              return _LiveReply(
                                text: state.liveText,
                                thinking: state.liveThinking,
                                tools: state.liveTools,
                                busy: state.busy,
                              );
                            }
                            return _EntryView(
                              entry: thread[index],
                              project: widget.project,
                            );
                          },
                        ),
                      ),
              ),
              if (_showJumpToBottom && thread.isNotEmpty)
                Positioned(
                  right: Sp.x4,
                  bottom: Sp.x2,
                  child: _JumpToBottom(
                    onTap: () => _scrollToEnd(force: true),
                  ),
                ),
            ],
          ),
        ),
        if (state.activeQuota.hasLimit &&
            (state.activeQuota.warning ||
                state.activeQuota.low ||
                state.activeQuota.exhausted))
          _QuotaWarning(
            used: state.activeQuota.used,
            limit: state.activeQuota.limit,
            exhausted: state.activeQuota.exhausted,
          ),
        if (!state.busy &&
            (state.checkpointFor(widget.project.id)?.resumable ?? false))
          _ResumeCard(
            checkpoint: state.checkpointFor(widget.project.id)!,
            onResume: () => state.resumeTask(widget.project.id),
            onDismiss: () => state.dismissCheckpoint(widget.project.id),
          ),
        _Composer(
          project: widget.project,
          controller: _composer,
          busy: state.busy,
          attachments: _attachments,
          onAttach: _pickAttachments,
          onRemove: (path) => setState(() => _attachments.remove(path)),
          onSend: _send,
          onStop: state.stop,
        ),
      ],
    );
  }
}

class _EmptyAgent extends StatelessWidget {
  const _EmptyAgent({required this.kind, required this.onPrompt});

  final ProjectKind kind;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final suggestions = switch (kind) {
      ProjectKind.web => const [
          'Add a responsive navigation bar',
          'Add a dark mode toggle to app.js',
          'Improve the landing page copy and layout',
        ],
      ProjectKind.flutter => const [
          'Add a settings screen with a theme switch',
          'Fix any layout overflow on a narrow screen',
          'Add a widget test for the main screen',
        ],
      ProjectKind.python => const [
          'Add command-line arguments to main.py',
          'Write tests for the Python functions',
          'Add a JSON configuration loader',
        ],
      ProjectKind.node => const [
          'Add a JSON API route to server.js',
          'Add request logging and graceful shutdown',
          'Write a test for the Node.js server',
        ],
      ProjectKind.php => const [
          'Add a form handler to index.php',
          'Add a JSON API endpoint',
          'Add input validation and error handling',
        ],
      ProjectKind.go => const [
          'Add an HTTP health endpoint',
          'Add command-line flags to main.go',
          'Write a Go test for the handler',
        ],
      ProjectKind.blank => const [
          'Create a README for this project',
          'Scaffold a small web app',
          'List the files and explain them',
        ],
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x6, Sp.page, Sp.x4),
      children: [
        Text('Ask for a change.', style: Txt.headline),
        const SizedBox(height: 8),
        Text(
          'Praxis reads and writes real files in this project. Replies stream in; '
          'tool calls become pills you can open to see the exact diff.',
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
                    Icon(Icons.arrow_outward_rounded,
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
  const _EntryView({required this.entry, required this.project});

  final ChatEntry entry;
  final Project project;

  @override
  Widget build(BuildContext context) {
    switch (entry.role) {
      case ChatRole.user:
        return _UserBubble(entry: entry, project: project);
      case ChatRole.assistant:
        return Padding(
          padding: const EdgeInsets.only(bottom: Sp.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AgentLabel(),
              if (entry.thinking.trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                _ThinkingPill(text: entry.thinking),
              ],
              if (entry.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                _MessageText(entry.text),
              ],
            ],
          ),
        );
      case ChatRole.tool:
        return _ToolPill(entry: entry);
      case ChatRole.activity:
        return _ActivityPill(entry: entry);
      case ChatRole.error:
        return Padding(
          padding: const EdgeInsets.only(bottom: Sp.x4),
          child: Panel(
            borderColor: Pal.rose.withOpacity(0.45),
            padding: const EdgeInsets.all(Sp.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 17, color: Pal.rose),
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
      case ChatRole.note:
        return Padding(
          padding: const EdgeInsets.only(bottom: Sp.x4),
          child: Row(
            children: [
              Expanded(child: Container(height: 1, color: Pal.line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 11, color: Pal.textDim),
                    const SizedBox(width: 4),
                    Text(
                      entry.text,
                      style: Txt.meta.copyWith(fontSize: 9),
                    ),
                  ],
                ),
              ),
              Expanded(child: Container(height: 1, color: Pal.line)),
            ],
          ),
        );
    }
  }
}

class _AgentLabel extends StatelessWidget {
  const _AgentLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const BrandMark(size: 12),
        const SizedBox(width: 6),
        Text(
          'PRAXIS',
          style: Txt.overline.copyWith(color: Pal.textMuted),
        ),
      ],
    );
  }
}

class _ActivityPill extends StatelessWidget {
  const _ActivityPill({required this.entry});

  final ChatEntry entry;

  IconData get _icon => switch (entry.tool) {
        'compact' => Icons.compress_rounded,
        'skill' => Icons.auto_stories_outlined,
        _ => Icons.data_object_rounded,
      };

  String get _label => switch (entry.tool) {
        'compact' => 'Compacted context',
        'skill' => 'Read skill',
        _ => 'Read context',
      };

  @override
  Widget build(BuildContext context) {
    final detail = entry.detail.trim();
    final color = entry.tool == 'compact' ? Pal.amber : Pal.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Pal.raised,
          borderRadius: Rd.pill,
          border: Border.all(color: Pal.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(
              _label,
              style: Txt.meta.copyWith(
                fontSize: 10,
                color: Pal.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(fontSize: 9.5, color: Pal.textDim),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageText extends StatelessWidget {
  const _MessageText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Txt.body.copyWith(height: 1.58));
  }
}

class _LiveReply extends StatelessWidget {
  const _LiveReply({
    required this.text,
    required this.thinking,
    required this.tools,
    required this.busy,
  });

  final String text;
  final String thinking;
  final List<ToolDraft> tools;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (!busy && text.isEmpty && thinking.isEmpty && tools.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AgentLabel(),
          if (thinking.isNotEmpty) ...[
            const SizedBox(height: 7),
            _ThinkingPill(text: thinking, live: true),
          ],
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _MessageText(text)),
                const _StreamCaret(),
              ],
            ),
          ] else if (busy && tools.isEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'Thinking…',
              style: Txt.meta.copyWith(color: Pal.textDim),
            ),
          ],
          for (final tool in tools)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: _DraftPill(draft: tool),
            ),
        ],
      ),
    );
  }
}

class _StreamCaret extends StatefulWidget {
  const _StreamCaret();

  @override
  State<_StreamCaret> createState() => _StreamCaretState();
}

class _StreamCaretState extends State<_StreamCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 15,
        margin: const EdgeInsets.only(left: 3, top: 4),
        color: Pal.ember,
      ),
    );
  }
}

class _DraftPill extends StatelessWidget {
  const _DraftPill({required this.draft});

  final ToolDraft draft;

  String get _verb => switch (draft.tool) {
        'write_file' => 'Writing',
        'read_file' => 'Reading',
        'run_command' => 'Running',
        'list_files' => 'Listing',
        _ => 'Running',
      };

  IconData get _icon => switch (draft.tool) {
        'write_file' => Icons.edit_note_rounded,
        'read_file' => Icons.description_outlined,
        'run_command' => Icons.terminal_rounded,
        'list_files' => Icons.folder_open_rounded,
        _ => Icons.build_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.ember.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          _PulseDot(),
          const SizedBox(width: 7),
          Icon(_icon, size: 14, color: Pal.ember),
          const SizedBox(width: 7),
          Text(
            draft.tool,
            style: Txt.meta.copyWith(
              color: Pal.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              draft.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Txt.meta.copyWith(fontSize: 10, color: Pal.textDim),
            ),
          ),
          Text(
            '$_verb…',
            style: Txt.meta.copyWith(
              fontSize: 9.5,
              color: Pal.ember,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_controller),
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: Pal.ember,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.entry, required this.project});

  final ChatEntry entry;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('YOU', style: Txt.overline.copyWith(color: Pal.textDim)),
          const SizedBox(height: 5),
          Container(
            constraints: BoxConstraints(maxWidth: width * 0.84),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: Pal.ember.withOpacity(0.10),
              border: Border.all(color: Pal.ember.withOpacity(0.22)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.text, style: Txt.body.copyWith(fontSize: 14.5)),
                if (entry.attachments.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final path in entry.attachments)
                        _AttachmentPreview(
                          path: path,
                          absolute: state.attachmentPath(project, path),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.path, required this.absolute});

  final String path;
  final String absolute;

  bool get _isImage =>
      RegExp(r'\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false)
          .hasMatch(path);

  String get _name => path.split('/').last;

  @override
  Widget build(BuildContext context) {
    if (_isImage) {
      return ClipRRect(
        borderRadius: Rd.sm,
        child: Image.file(
          File(absolute),
          width: 84,
          height: 84,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) =>
              MonoChip(_name, icon: Icons.image_outlined),
        ),
      );
    }
    return MonoChip(_name, icon: Icons.description_outlined);
  }
}

class _ThinkingPill extends StatefulWidget {
  const _ThinkingPill({required this.text, this.live = false});

  final String text;
  final bool live;

  @override
  State<_ThinkingPill> createState() => _ThinkingPillState();
}

class _ThinkingPillState extends State<_ThinkingPill> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Pal.raised,
              borderRadius: Rd.pill,
              border: Border.all(color: Pal.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.live
                      ? Icons.psychology_rounded
                      : Icons.psychology_alt_outlined,
                  size: 13,
                  color: widget.live ? Pal.ember : Pal.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.live ? 'Thinking live' : 'Thinking',
                  style: Txt.meta.copyWith(
                    color: widget.live ? Pal.text : Pal.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 15,
                  color: Pal.textDim,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          GestureDetector(
            onTap: () => setState(() => _open = false),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                color: Pal.ghBg,
                borderRadius: Rd.sm,
                border: Border.all(color: Pal.ghLine),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.text,
                  style: Txt.code.copyWith(
                    fontSize: 11,
                    height: 1.55,
                    color: Pal.ghMuted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToolPill extends StatefulWidget {
  const _ToolPill({required this.entry});

  final ChatEntry entry;

  @override
  State<_ToolPill> createState() => _ToolPillState();
}

class _ToolPillState extends State<_ToolPill> {
  bool _open = false;

  ChatEntry get entry => widget.entry;

  IconData get _icon => switch (entry.tool) {
        'write_file' => Icons.edit_note_rounded,
        'read_file' => Icons.description_outlined,
        'read_files' => Icons.description_outlined,
        'run_command' => Icons.terminal_rounded,
        'list_files' => Icons.folder_open_rounded,
        _ => Icons.build_outlined,
      };

  bool get _failed => entry.text.toLowerCase().startsWith('error') || !entry.ok;

  @override
  Widget build(BuildContext context) {
    final diff = FileDiff.decode(entry.patch);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Pal.raised,
                borderRadius: Rd.sm,
                border: Border.all(
                  color: _failed ? Pal.rose.withOpacity(0.4) : Pal.line,
                ),
              ),
              child: Row(
                children: [
                  Icon(_icon, size: 14, color: _failed ? Pal.rose : Pal.mint),
                  const SizedBox(width: 7),
                  Text(
                    entry.tool,
                    style: Txt.meta.copyWith(
                      color: _failed ? Pal.rose : Pal.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      entry.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Txt.meta.copyWith(fontSize: 10, color: Pal.textDim),
                    ),
                  ),
                  if (entry.added > 0 || entry.removed > 0) ...[
                    Text(
                      '+${entry.added}',
                      style: Txt.meta.copyWith(
                        fontSize: 10,
                        color: Pal.ghAddText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '-${entry.removed}',
                      style: Txt.meta.copyWith(
                        fontSize: 10,
                        color: Pal.ghDelText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: Pal.textDim,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            GestureDetector(
              onTap: () => setState(() => _open = false),
              behavior: HitTestBehavior.opaque,
              child: _ToolBody(entry: entry, diff: diff),
            ),
        ],
      ),
    );
  }
}

class _ToolBody extends StatelessWidget {
  const _ToolBody({required this.entry, required this.diff});

  final ChatEntry entry;
  final FileDiff? diff;

  @override
  Widget build(BuildContext context) {
    final content = entry.text.trim();
    if (diff != null && diff!.rows.isNotEmpty) {
      return _DiffTable(diff: diff!);
    }
    if (content.isEmpty) return const SizedBox.shrink();
    if (entry.tool == 'read_files') {
      return _ReadFilesBody(text: content);
    }
    final numbered = entry.tool == 'read_file' || entry.tool == 'list_files';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        color: Pal.ghBg,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.ghLine),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: numbered
              ? _NumberedText(text: content)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    content,
                    style: Txt.code.copyWith(
                      fontSize: 11,
                      height: 1.55,
                      color: entry.tool == 'run_command'
                          ? Pal.ghText
                          : Pal.ghMuted,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Only additions and removals are shown. Unchanged lines stay out of the
/// transcript; the line numbers make the surrounding code legible.
class _DiffTable extends StatelessWidget {
  const _DiffTable({required this.diff});

  final FileDiff diff;

  @override
  Widget build(BuildContext context) {
    final rows = diff.rows
        .where((row) => row.kind != DiffKind.context)
        .toList(growable: false);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        color: Pal.ghBg,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.ghLine),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final added = row.kind == DiffKind.added;
            final removed = row.kind == DiffKind.removed;
            return Container(
              color: added
                  ? Pal.ghAddBg
                  : removed
                      ? Pal.ghDelBg
                      : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      row.oldLine?.toString() ?? '',
                      textAlign: TextAlign.right,
                      style: Txt.meta.copyWith(
                        fontSize: 9,
                        height: 1.55,
                        color: Pal.ghMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: 30,
                    child: Text(
                      row.newLine?.toString() ?? '',
                      textAlign: TextAlign.right,
                      style: Txt.meta.copyWith(
                        fontSize: 9,
                        height: 1.55,
                        color: Pal.ghMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: 10,
                    child: Text(
                      added ? '+' : '-',
                      style: Txt.meta.copyWith(
                        fontSize: 10,
                        height: 1.4,
                        color: added ? Pal.ghAddText : Pal.ghDelText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.text.isEmpty ? ' ' : row.text,
                      style: Txt.code.copyWith(
                        fontSize: 10.5,
                        height: 1.45,
                        color: Pal.ghText,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NumberedText extends StatelessWidget {
  const _NumberedText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final shown = lines.length <= 400 ? lines : lines.take(400).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.right,
                    style: Txt.meta.copyWith(
                      fontSize: 9,
                      height: 1.5,
                      color: Pal.ghMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    shown[i].isEmpty ? ' ' : shown[i],
                    style: Txt.code.copyWith(
                      fontSize: 10.5,
                      height: 1.45,
                      color: Pal.ghText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (lines.length > 400)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              '… ${lines.length - 400} more lines',
              style: Txt.meta.copyWith(color: Pal.textDim),
            ),
          ),
      ],
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.project,
    required this.controller,
    required this.busy,
    required this.attachments,
    required this.onAttach,
    required this.onRemove,
    required this.onSend,
    required this.onStop,
  });

  final Project project;
  final TextEditingController controller;
  final bool busy;
  final List<String> attachments;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemove;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final List<_ComposerSuggestion> _suggestions = [];
  final List<_ComposerSuggestion> _skills = [];
  List<String>? _files;
  Timer? _debounce;
  String? _trigger;
  int _tokenStart = 0;
  bool _loadedContext = false;
  bool _loadingFiles = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedContext) {
      _loadedContext = true;
      _loadSkills();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  Future<void> _loadSkills() async {
    final state = AppScope.of(context);
    final projectSkills = await state.installedSkillsFor(widget.project);
    if (!mounted) return;
    final seen = <String>{};
    void add(String label, String command, String detail) {
      if (!seen.add(command)) return;
      _skills.add(_ComposerSuggestion(
        label: label,
        insert: '/$command ',
        detail: detail,
        icon: Icons.extension_outlined,
      ));
    }

    for (final skill in state.skills.where((skill) => skill.enabled)) {
      final command =
          skill.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      if (command.isNotEmpty) add(skill.name, command, 'Enabled skill');
    }
    for (final skill in projectSkills) {
      add(skill.name, skill.slug, 'Project skill');
    }
    _skills.sort((a, b) => a.label.compareTo(b.label));
    if (mounted) _refreshSuggestions();
  }

  Future<void> _loadFiles() async {
    if (_loadingFiles || _files != null) return;
    _loadingFiles = true;
    final state = AppScope.of(context);
    try {
      final entries =
          await state.fsFor(widget.project).list(includeHidden: true);
      if (!mounted) return;
      _files = [
        for (final entry in entries)
          if (!entry.isDir && !entry.path.startsWith('.praxis/')) entry.path,
      ]..sort();
      _refreshSuggestions();
    } catch (_) {
      _files = const [];
    } finally {
      _loadingFiles = false;
    }
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 90), _refreshSuggestions);
  }

  void _hideSuggestions() {
    if (_suggestions.isEmpty) return;
    setState(() {
      _suggestions.clear();
      _trigger = null;
    });
  }

  void _refreshSuggestions() {
    if (!mounted) return;
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _hideSuggestions();
      return;
    }
    final before = widget.controller.text.substring(0, selection.baseOffset);
    final match =
        RegExp(r'(?:^|\s)([/@])([A-Za-z0-9._/-]*)$').firstMatch(before);
    if (match == null) {
      _hideSuggestions();
      return;
    }
    final trigger = match.group(1)!;
    final query = match.group(2)!.toLowerCase();
    if (trigger == '/' && query.isEmpty) {
      _hideSuggestions();
      return;
    }
    if (trigger == '@' && _files == null) {
      _loadFiles();
    }
    final tokenStart = selection.baseOffset - query.length - 1;
    final pool = trigger == '/'
        ? _skills
        : [
            for (final path in _files ?? const <String>[])
              _ComposerSuggestion(
                label: path.split('/').last,
                insert: '@$path ',
                detail: path,
                icon: Icons.description_outlined,
              ),
          ];
    final filtered = pool
        .where((item) =>
            query.isEmpty ||
            item.label.toLowerCase().contains(query) ||
            item.detail.toLowerCase().contains(query))
        .take(7)
        .toList();
    setState(() {
      _trigger = trigger;
      _tokenStart = tokenStart < 0 ? 0 : tokenStart;
      _suggestions
        ..clear()
        ..addAll(filtered);
    });
  }

  void _choose(_ComposerSuggestion suggestion) {
    final selection = widget.controller.selection;
    if (!selection.isValid) return;
    final text = widget.controller.text;
    final caret = selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, caret);
    final match =
        RegExp(r'(?:^|\s)([/@])([A-Za-z0-9._/-]*)$').firstMatch(before);
    // Work out the token from the text that is on screen now. A suggestion can
    // arrive after the caret moved, and replacing a stale range deleted part of
    // the command the user had already typed.
    final start = match == null
        ? _tokenStart.clamp(0, caret)
        : caret - match.group(2)!.length - 1;
    final updated = text.replaceRange(start, caret, suggestion.insert);
    widget.controller.value = TextEditingValue(
      text: updated,
      // A collapsed caret keeps the completion. Selecting it meant the next key
      // press replaced the whole skill name with that letter.
      selection: TextSelection.collapsed(
        offset: start + suggestion.insert.length,
      ),
    );
    setState(() {
      _suggestions.clear();
      _trigger = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(Sp.x3, 0, Sp.x3, 4),
            decoration: BoxDecoration(
              color: Pal.surface,
              borderRadius: Rd.md,
              border: Border.all(color: Pal.lineStrong),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(Pal.isDark ? 0.28 : 0.08),
                  offset: const Offset(0, 4),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 3),
                  child: Row(
                    children: [
                      Icon(
                        _trigger == '/'
                            ? Icons.bolt_rounded
                            : Icons.tag_rounded,
                        size: 13,
                        color: Pal.ember,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _trigger == '/'
                            ? 'Skills · click to complete'
                            : 'Project files · click to tag',
                        style: Txt.meta.copyWith(fontSize: 8.5),
                      ),
                    ],
                  ),
                ),
                for (final suggestion in _suggestions)
                  InkWell(
                    onTap: () => _choose(suggestion),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                      child: Row(
                        children: [
                          Icon(suggestion.icon, size: 14, color: Pal.mint),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(suggestion.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Txt.code.copyWith(fontSize: 11)),
                                if (suggestion.detail.isNotEmpty)
                                  Text(
                                    suggestion.detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Txt.meta.copyWith(fontSize: 8.5),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            _trigger == '/' ? suggestion.insert.trim() : '@',
                            style: Txt.meta.copyWith(
                              fontSize: 8.5,
                              color: Pal.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        _ComposerBody(
          controller: widget.controller,
          busy: widget.busy,
          attachments: widget.attachments,
          onAttach: widget.onAttach,
          onRemove: widget.onRemove,
          onSend: widget.onSend,
          onStop: widget.onStop,
        ),
      ],
    );
  }
}

class _ComposerSuggestion {
  const _ComposerSuggestion({
    required this.label,
    required this.insert,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String insert;
  final String detail;
  final IconData icon;
}

class _ComposerBody extends StatelessWidget {
  const _ComposerBody({
    required this.controller,
    required this.busy,
    required this.attachments,
    required this.onAttach,
    required this.onRemove,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool busy;
  final List<String> attachments;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemove;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Sp.x3,
        Sp.x1,
        Sp.x3,
        mathMax(12, MediaQuery.paddingOf(context).bottom + 8),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
        decoration: BoxDecoration(
          color: Pal.surface,
          borderRadius: Rd.lg,
          border: Border.all(color: Pal.lineStrong),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(Pal.isDark ? 0.30 : 0.08),
              offset: const Offset(0, 6),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: attachments.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final path = attachments[index];
                      final name = path.split('/').last;
                      return Container(
                        padding: const EdgeInsets.only(left: 9, right: 4),
                        decoration: BoxDecoration(
                          color: Pal.raised,
                          borderRadius: Rd.pill,
                          border: Border.all(color: Pal.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.attach_file_rounded,
                                size: 12, color: Pal.textDim),
                            const SizedBox(width: 5),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Txt.meta.copyWith(fontSize: 10),
                              ),
                            ),
                            IconAction(
                              icon: Icons.close_rounded,
                              tooltip: 'Remove attachment',
                              size: 12,
                              onTap: () => onRemove(path),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: IconAction(
                      icon: Icons.attach_file_rounded,
                      tooltip: 'Attach a photo or file',
                      size: 19,
                      onTap: busy ? null : onAttach,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: Txt.body.copyWith(fontSize: 14),
                    cursorColor: Pal.ember,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      filled: true,
                      fillColor: Pal.raised,
                      hintText: busy ? 'Working…' : 'Ask for a change',
                      hintStyle: Txt.bodySoft.copyWith(color: Pal.textDim),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: Rd.md,
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: Rd.md,
                        borderSide:
                            BorderSide(color: Pal.ember.withOpacity(0.45)),
                      ),
                    ),
                    onSubmitted: busy ? null : (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 7),
                GestureDetector(
                  onTap: busy ? onStop : onSend,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: busy ? Pal.rose : Pal.ember,
                      borderRadius: Rd.md,
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
          ],
        ),
      ),
    );
  }
}

class _JumpToBottom extends StatelessWidget {
  const _JumpToBottom({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Jump to latest message',
      child: Tooltip(
        message: 'Jump to latest',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Pal.surface,
              shape: BoxShape.circle,
              border: Border.all(color: Pal.ember.withOpacity(0.42)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(Pal.isDark ? 0.26 : 0.08),
                  offset: const Offset(0, 4),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Icon(
              Icons.keyboard_double_arrow_down_rounded,
              size: 21,
              color: Pal.ember,
            ),
          ),
        ),
      ),
    );
  }
}

double mathMax(double a, double b) => a > b ? a : b;

class _QuotaWarning extends StatelessWidget {
  const _QuotaWarning({
    required this.used,
    required this.limit,
    required this.exhausted,
  });

  final int used;
  final int limit;
  final bool exhausted;

  @override
  Widget build(BuildContext context) {
    final color = exhausted ? Pal.rose : Pal.amber;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.x3, 0, Sp.x3, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: Rd.sm,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            exhausted ? Icons.block_rounded : Icons.speed_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              exhausted
                  ? '$used/$limit requests used today. This provider has no requests left for today.'
                  : '$used/$limit requests used today. This task may use the rest of today\'s allowance.',
              style: Txt.meta.copyWith(fontSize: 9.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.checkpoint,
    required this.onResume,
    required this.onDismiss,
  });

  final TaskCheckpoint checkpoint;
  final VoidCallback onResume;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.x3, 0, Sp.x3, 6),
      padding: const EdgeInsets.fromLTRB(11, 10, 8, 8),
      decoration: BoxDecoration(
        color: Pal.ember.withOpacity(0.07),
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.ember.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restore_rounded, size: 15, color: Pal.ember),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Task paused · ${checkpoint.completed.length} completed',
                  style: Txt.label.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconAction(
                icon: Icons.close_rounded,
                tooltip: 'Dismiss checkpoint',
                size: 15,
                onTap: onDismiss,
              ),
            ],
          ),
          if (checkpoint.pendingStep.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(
                checkpoint.pendingStep,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Txt.meta.copyWith(fontSize: 9.5, height: 1.4),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${checkpoint.changedFiles.length} changed files · '
                  '${checkpoint.providerName} ${checkpoint.model}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(fontSize: 8.5),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onResume,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Pal.ember,
                    borderRadius: Rd.sm,
                  ),
                  child: Text(
                    'Resume',
                    style: Txt.label.copyWith(
                      fontSize: 10,
                      color: Pal.onEmber,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadFilesBody extends StatelessWidget {
  const _ReadFilesBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final matches =
        RegExp(r'^\[(.+?) · lines', multiLine: true).allMatches(text).toList();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.line),
      ),
      child: matches.isEmpty
          ? Text(
              text,
              style: Txt.code.copyWith(fontSize: 10.5, height: 1.5),
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final match in matches)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Pal.surface,
                      borderRadius: Rd.sm,
                      border: Border.all(color: Pal.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined,
                            size: 12, color: Pal.sky),
                        const SizedBox(width: 5),
                        Text(
                          match.group(1) ?? '',
                          style: Txt.code.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
