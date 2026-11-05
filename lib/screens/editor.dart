import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/code_editor.dart';
import '../widgets/ui.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.project, required this.path});

  final Project project;
  final String path;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final CodeController _controller =
      CodeController(language: languageForPath(widget.path));
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  String? _error;
  late bool _preview = _isMarkdown;
  final _previewScroll = ScrollController();

  bool get _isMarkdown => languageForPath(widget.path) == CodeLanguage.markdown;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  void _togglePreview() {
    setState(() => _preview = !_preview);
    if (_preview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_previewScroll.hasClients) _previewScroll.jumpTo(0);
      });
    }
  }

  Future<void> _load() async {
    try {
      final content =
          await AppScope.of(context).readFile(widget.project, widget.path);
      if (!mounted) return;
      setState(() {
        _controller.text = content;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppScope.of(context)
          .writeFile(widget.project, widget.path, _controller.text);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      messenger.showSnackBar(SnackBar(content: Text('Saved ${widget.path}')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save: $error')),
      );
    }
  }

  Future<void> _confirmLeave() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Discard changes?'),
        content: Text('${widget.path} has unsaved edits.', style: Txt.bodySoft),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Pal.rose),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final language = languageForPath(widget.path);
    final lines = _controller.text.split('\n').length;

    return Scaffold(
      backgroundColor: _preview ? Pal.canvas : Pal.ghBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Pal.ghPanel,
              padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
              child: Row(
                children: [
                  IconAction(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: _confirmLeave,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.path.split('/').last,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Txt.title.copyWith(fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 8),
                            MonoChip(_isMarkdown && _preview
                                ? 'Markdown'
                                : language.label),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dirty
                              ? 'unsaved changes · $lines lines'
                              : 'saved on device · $lines lines',
                          style: Txt.meta.copyWith(
                            fontSize: 10,
                            color: _dirty ? Pal.amber : Pal.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isMarkdown)
                    GestureDetector(
                      onTap: _togglePreview,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          color: Pal.raised,
                          borderRadius: Rd.pill,
                          border: Border.all(color: Pal.lineStrong),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _preview
                                  ? Icons.code_rounded
                                  : Icons.article_outlined,
                              size: 14,
                              color: Pal.textMuted,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _preview ? 'Code' : 'Preview',
                              style: Txt.meta.copyWith(
                                fontSize: 10,
                                color: Pal.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!_preview)
                    IconAction(
                      icon: state.wordWrap
                          ? Icons.wrap_text_rounded
                          : Icons.notes_rounded,
                      tooltip:
                          state.wordWrap ? 'Disable wrapping' : 'Wrap lines',
                      size: 18,
                      onTap: () => state.setWordWrap(!state.wordWrap),
                    ),
                  const SizedBox(width: 2),
                  EmberButton(
                    label: _saving ? 'Saving' : 'Save',
                    compact: true,
                    loading: _saving,
                    onTap: _save,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(Sp.page),
                          child: Text(
                            _error!,
                            style: Txt.bodySoft.copyWith(color: Pal.rose),
                          ),
                        )
                      : _preview
                          ? _MarkdownPreview(
                              data: _controller.text,
                              path: widget.path,
                              controller: _previewScroll,
                            )
                          : CodeEditor(
                              controller: _controller,
                              language: language,
                              wrap: state.wordWrap,
                              onChanged: (_) {
                                if (!_dirty) setState(() => _dirty = true);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({
    required this.data,
    required this.path,
    required this.controller,
  });

  final String data;
  final String path;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Pal.canvas,
      child: Scrollbar(
        controller: controller,
        child: SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(Sp.x5, Sp.x4, Sp.x5, Sp.x8),
          child: MarkdownBody(
            data: data.isEmpty ? '_This file is empty._' : data,
            selectable: true,
            onTapLink: (text, href, title) {
              if (href == null || href.isEmpty) return;
              Clipboard.setData(ClipboardData(text: href));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Link copied: $href')),
              );
            },
            styleSheet: MarkdownStyleSheet(
              p: Txt.body.copyWith(height: 1.65),
              h1: Txt.headline.copyWith(fontSize: 27),
              h2: Txt.headline.copyWith(fontSize: 22),
              h3: Txt.title.copyWith(fontSize: 18),
              h4: Txt.title.copyWith(fontSize: 16),
              strong: Txt.body.copyWith(fontWeight: FontWeight.w700),
              em: Txt.body.copyWith(fontStyle: FontStyle.italic),
              a: Txt.body.copyWith(
                color: Pal.ember,
                decoration: TextDecoration.underline,
                decorationColor: Pal.ember,
              ),
              code: Txt.code.copyWith(
                fontSize: 12,
                color: Pal.ghText,
                backgroundColor: Pal.ghPanel,
              ),
              codeblockDecoration: BoxDecoration(
                color: Pal.ghBg,
                borderRadius: Rd.sm,
                border: Border.all(color: Pal.ghLine),
              ),
              codeblockPadding: const EdgeInsets.all(Sp.x3),
              blockquote: Txt.bodySoft.copyWith(
                fontStyle: FontStyle.italic,
                color: Pal.textMuted,
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(left: BorderSide(color: Pal.ember, width: 2)),
              ),
              blockquotePadding: const EdgeInsets.only(left: Sp.x4),
              listBullet: Txt.body,
              horizontalRuleDecoration: BoxDecoration(
                border: Border(top: BorderSide(color: Pal.line)),
              ),
              tableHead: Txt.label.copyWith(fontWeight: FontWeight.w700),
              tableBody: Txt.bodySoft,
              tableBorder: TableBorder.all(color: Pal.line),
              tableCellsPadding: const EdgeInsets.all(8),
            ),
          ),
        ),
      ),
    );
  }
}
