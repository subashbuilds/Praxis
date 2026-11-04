import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/diff.dart';
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
  int _lastCount = 0;
  AppState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    _state = state;
    state.limitPrompt = _askLimit;
  }

  @override
  void dispose() {
    final state = _state;
    if (state != null) state.limitPrompt = null;
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _askLimit(String title, String body, String accept) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: Text(title),
        content: Text(body, style: Txt.bodySoft),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stop'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(accept),
          ),
        ],
      ),
    );
    return result ?? false;
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
              leading: const Icon(Icons.image_outlined, color: Pal.textMuted),
              title: const Text('Photos'),
              subtitle: const Text('Images from the gallery'),
              onTap: () => Navigator.of(sheetContext).pop('image'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.attach_file_rounded, color: Pal.textMuted),
              title: const Text('Any file'),
              subtitle: const Text('Text, PDF, zip — copied into the project'),
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
    setState(_attachments.clear);
    _scrollToEnd();
    await AppScope.of(context)
        .send(widget.project.id, text, attachments: files);
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
                      const EdgeInsets.fromLTRB(Sp.x4, Sp.x4, Sp.x4, Sp.x4),
                  itemCount: thread.length,
                  itemBuilder: (context, index) => _EntryView(
                    entry: thread[index],
                    project: widget.project,
                  ),
                ),
        ),
        _Composer(
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
          'The agent reads and writes real files in this project. Tool calls '
          'collapse into pills; tap one to see its diff.',
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
              if (entry.thinking.trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                _ThinkingPill(text: entry.thinking),
              ],
              if (entry.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(entry.text, style: Txt.body.copyWith(height: 1.55)),
              ],
            ],
          ),
        );
      case ChatRole.tool:
        return _ToolPill(entry: entry);
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
          errorBuilder: (context, error, stack) => MonoChip(
            _name,
            icon: Icons.image_outlined,
          ),
        ),
      );
    }
    return MonoChip(_name, icon: Icons.description_outlined);
  }
}

class _ThinkingPill extends StatefulWidget {
  const _ThinkingPill({required this.text});

  final String text;

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
                const Icon(Icons.psychology_alt_outlined,
                    size: 13, color: Pal.textMuted),
                const SizedBox(width: 6),
                Text(
                  'Thinking',
                  style: Txt.meta.copyWith(
                    color: Pal.textMuted,
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
              constraints: const BoxConstraints(maxHeight: 280),
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
                      style: Txt.meta.copyWith(
                        fontSize: 10,
                        color: Pal.textDim,
                      ),
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

class _DiffTable extends StatelessWidget {
  const _DiffTable({required this.diff});

  final FileDiff diff;

  @override
  Widget build(BuildContext context) {
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
          itemCount: diff.rows.length,
          itemBuilder: (context, index) {
            final row = diff.rows[index];
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
                      added
                          ? '+'
                          : removed
                              ? '-'
                              : ' ',
                      style: Txt.meta.copyWith(
                        fontSize: 10,
                        height: 1.4,
                        color: added
                            ? Pal.ghAddText
                            : removed
                                ? Pal.ghDelText
                                : Pal.ghMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.text.isEmpty ? ' ' : row.text,
                      style: Txt.code.copyWith(
                        fontSize: 10.5,
                        height: 1.45,
                        color: added
                            ? Pal.ghText
                            : removed
                                ? Pal.ghText
                                : Pal.ghMuted,
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

class _Composer extends StatelessWidget {
  const _Composer({
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
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Pal.line)),
      ),
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x2, Sp.x3, Sp.x2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
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
                          const Icon(Icons.attach_file_rounded,
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconAction(
                icon: Icons.attach_file_rounded,
                tooltip: 'Attach a photo or file',
                size: 18,
                onTap: busy ? null : onAttach,
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
        ],
      ),
    );
  }
}
