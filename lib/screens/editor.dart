import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/file_types.dart';
import '../core/readme_html.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/code_editor.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/file_glyph.dart';
import '../widgets/readme_image.dart';
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
  late FileTypeInfo _type = classifyFile(widget.path);
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  bool _binary = false;
  bool _image = false;
  bool _svg = false;
  bool _preview = false;
  Uint8List? _bytes;
  String? _error;
  final _previewScroll = ScrollController();
  AppState? _appState;
  bool _markedActive = false;

  bool get _isMarkdown => languageForPath(widget.path) == CodeLanguage.markdown;
  bool get _canEdit => !_image && !_binary;
  bool get _hasPreview => _isMarkdown || _svg;

  String get _typeLabel {
    if (_svg) return 'SVG';
    if (_image) return _type.label;
    if (_isMarkdown) return 'Markdown';
    return languageForPath(widget.path).label;
  }

  int get _lineCount => _controller.text.split('\n').length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    _appState = state;
    if (!_markedActive) {
      _markedActive = true;
      state.setActiveFile(widget.project.id, widget.path);
    }
  }

  @override
  void dispose() {
    _appState?.setActiveFile(widget.project.id, null);
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
      final bytes =
          await AppScope.of(context).readFileBytes(widget.project, widget.path);
      final type = classifyFile(widget.path, bytes: bytes);
      final image = type.kind == FileKind.image;
      final svg = type.kind == FileKind.svg;
      final text = image ? null : decodeUtf8(bytes, allowEmpty: true);
      final binary =
          !svg && (image || type.kind == FileKind.binary || text == null);
      if (!mounted) return;
      setState(() {
        _type = type;
        _bytes = bytes;
        _image = image;
        _svg = svg;
        _binary = binary;
        _preview = image || svg || (_isMarkdown && !binary);
        if (!binary && text != null) _controller.text = text;
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
    if (_saving || !_canEdit) return;
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
    final leave = await showPraxisConfirm(
      context,
      title: 'Discard changes?',
      body: '${widget.path} has unsaved edits. Leaving now keeps the version '
          'that is already on this device.',
      confirmLabel: 'Discard edits',
      cancelLabel: 'Keep editing',
      destructive: true,
      icon: Icons.edit_off_rounded,
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final language = languageForPath(widget.path);
    return Scaffold(
      backgroundColor: _preview ? Pal.canvas : Pal.ghBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Pal.ghPanel,
              padding: const EdgeInsets.all(Sp.x2),
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
                            FileGlyph(
                              name: widget.path.split('/').last,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.path.split('/').last,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Txt.title.copyWith(fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 8),
                            MonoChip(_typeLabel),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _loading
                              ? 'reading file…'
                              : _binary || _image
                                  ? '${humanFileSize(_bytes?.length ?? 0)} · saved on device'
                                  : _dirty
                                      ? 'unsaved changes · $_lineCount lines'
                                      : 'saved on device · $_lineCount lines',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.meta.copyWith(
                            fontSize: 10,
                            color: _dirty ? Pal.amber : Pal.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hasPreview)
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
                  if (!_preview && _canEdit)
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
                  if (_canEdit)
                    EmberButton(
                      label: _saving ? 'Saving' : 'Save',
                      compact: true,
                      loading: _saving,
                      onTap: _save,
                    ),
                ],
              ),
            ),
            Expanded(child: _content(language, state.wordWrap)),
          ],
        ),
      ),
    );
  }

  Widget _content(CodeLanguage language, bool wrap) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(Sp.page),
        children: [
          EmptyState(
            icon: Icons.warning_amber_rounded,
            title: 'Could not open this file',
            body: _error!,
          ),
        ],
      );
    }
    if (_image && _preview) return _imagePreview();
    if (_svg && _preview) return _svgPreview();
    if (_binary) return _binaryPreview();
    if (_isMarkdown && _preview) {
      return _MarkdownPreview(
        data: markdownFromReadme(_controller.text),
        controller: _previewScroll,
      );
    }
    return CodeEditor(
      controller: _controller,
      language: language,
      wrap: wrap,
      onChanged: (_) {
        if (!_dirty) setState(() => _dirty = true);
      },
    );
  }

  Widget _imagePreview() {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.shrink();
    return Container(
      color: Pal.canvas,
      padding: const EdgeInsets.all(Sp.x4),
      child: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text(
              'This image format cannot be rendered on this device.\n'
              'The file is intact and will still be committed byte for byte.',
              textAlign: TextAlign.center,
              style: Txt.bodySoft,
            ),
          ),
        ),
      ),
    );
  }

  Widget _svgPreview() {
    try {
      return Container(
        color: Pal.canvas,
        padding: const EdgeInsets.all(Sp.x4),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            child: SvgPicture.string(
              _controller.text,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    } catch (_) {
      return Center(
        child: Text('This SVG could not be rendered. Use Code to inspect it.',
            style: Txt.bodySoft),
      );
    }
  }

  Widget _binaryPreview() {
    return ListView(
      padding: const EdgeInsets.all(Sp.page),
      children: [
        EmptyState(
          icon: Icons.data_object_rounded,
          title: 'Binary file',
          body: '${widget.path} is ${humanFileSize(_bytes?.length ?? 0)} of '
              '${_type.mime ?? 'binary data'}. Praxis keeps the original bytes '
              'untouched; there is no text representation to edit here.',
        ),
        const SizedBox(height: Sp.x4),
        Panel(
          padding: const EdgeInsets.all(Sp.x3),
          child: Row(
            children: [
              Icon(Icons.verified_outlined, size: 16, color: Pal.mint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Safe to browse, copy and commit. The text editor will not '
                  'attempt to decode it.',
                  style: Txt.meta.copyWith(height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({
    required this.data,
    required this.controller,
  });

  final String data;
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
            imageBuilder: (uri, title, alt) =>
                ReadmeImage(uri: uri, title: title, alt: alt),
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
              tableColumnWidth: const FlexColumnWidth(),
              blockSpacing: 10,
            ),
          ),
        ),
      ),
    );
  }
}
