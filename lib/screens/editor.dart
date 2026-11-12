import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/file_types.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/code_editor.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/file_glyph.dart';
import '../widgets/github_markdown.dart';
import '../widgets/ui.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.project,
    required this.path,
    this.initialLine,
    this.highlight,
  });

  final Project project;
  final String path;

  /// Opens the file scrolled to this 1-based line, used by project search.
  final int? initialLine;

  /// Selects the first occurrence of this text on [initialLine].
  final String? highlight;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final CodeController _controller =
      CodeController(language: languageForPath(widget.path));
  late final UndoHistoryController _undo = UndoHistoryController();
  final _find = TextEditingController();
  final _findFocus = FocusNode();
  late FileTypeInfo _type = classifyFile(widget.path);
  bool _searchOpen = false;
  List<int> _findStarts = const [];
  List<int> _findEnds = const [];
  int _findIndex = 0;
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  bool _binary = false;
  bool _tooLarge = false;
  bool _forceOpen = false;
  bool _saved = false;
  bool _image = false;
  bool _svg = false;
  bool _preview = false;
  bool? _markdownDark;
  Uint8List? _bytes;
  String? _error;
  AppState? _appState;
  bool _markedActive = false;

  bool get _isMarkdown => languageForPath(widget.path) == CodeLanguage.markdown;
  bool get _canEdit => !_image && !_binary && !_tooLarge;
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
    _undo.addListener(_historyChanged);
    _load();
  }

  void _historyChanged() {
    if (mounted) setState(() {});
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
    _undo.removeListener(_historyChanged);
    _undo.dispose();
    _find.dispose();
    _findFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _togglePreview() {
    setState(() => _preview = !_preview);
  }

  void _toggleFind() {
    setState(() => _searchOpen = !_searchOpen);
    if (_searchOpen) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _findFocus.requestFocus());
    } else {
      _find.clear();
      _findStarts = const [];
      _findEnds = const [];
      _findIndex = 0;
    }
  }

  void _runFind(String query) {
    final starts = <int>[];
    final ends = <int>[];
    final text = _controller.text;
    if (query.trim().length >= 2) {
      final lowerText = text.toLowerCase();
      final lowerQuery = query.toLowerCase();
      var from = 0;
      while (true) {
        final found = lowerText.indexOf(lowerQuery, from);
        if (found < 0) break;
        starts.add(found);
        ends.add(found + query.length);
        from = found + query.length;
        if (starts.length >= 500) break;
      }
    }
    setState(() {
      _findStarts = starts;
      _findEnds = ends;
      _findIndex = 0;
    });
    _selectFind(0);
  }

  void _selectFind(int index) {
    if (_findStarts.isEmpty) return;
    final next = (index % _findStarts.length);
    setState(() => _findIndex = next);
    _controller.selection = TextSelection(
      baseOffset: _findStarts[next],
      extentOffset: _findEnds[next],
    );
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
      // A megabyte of text is thousands of laid-out lines. Opening it made the
      // whole workspace stutter, so ask before loading it into the editor.
      final oversized =
          !binary && !svg && (text?.length ?? 0) > 500000 && !_forceOpen;
      if (!mounted) return;
      setState(() {
        _type = type;
        _bytes = bytes;
        _image = image;
        _svg = svg;
        _binary = binary;
        _tooLarge = oversized;
        _preview = widget.initialLine == null &&
            (image || svg || (_isMarkdown && !binary));
        if (!binary && text != null && !oversized) _controller.text = text;
        _loading = false;
      });
      final query = widget.highlight?.trim() ?? '';
      if (widget.initialLine != null || query.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (query.isNotEmpty) {
            // Opening a project-search hit starts a find session, so every
            // occurrence is highlighted and the arrows step through them.
            _find.text = widget.highlight!;
            setState(() => _searchOpen = true);
            _runFind(widget.highlight!);
            if (widget.initialLine != null) {
              _selectFind(_findIndexForLine(widget.initialLine!));
            }
          } else if (widget.initialLine != null) {
            _jumpToLine(widget.initialLine!, null);
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  int _findIndexForLine(int line) {
    if (_findStarts.isEmpty) return 0;
    final lines = _controller.text.split('\n');
    final index = (line - 1).clamp(0, lines.length - 1);
    var start = 0;
    for (var i = 0; i < index; i++) {
      start += lines[i].length + 1;
    }
    for (var i = 0; i < _findStarts.length; i++) {
      if (_findStarts[i] >= start) return i;
    }
    return _findStarts.length - 1;
  }

  void _jumpToLine(int line, String? query) {
    final text = _controller.text;
    final lines = text.split('\n');
    if (lines.isEmpty) return;
    final index = (line - 1).clamp(0, lines.length - 1);
    var start = 0;
    for (var i = 0; i < index; i++) {
      start += lines[i].length + 1;
    }
    final lineText = lines[index];
    var from = 0;
    var to = lineText.length;
    final needle = (query ?? '').trim();
    if (needle.isNotEmpty) {
      final found = lineText.toLowerCase().indexOf(needle.toLowerCase());
      if (found >= 0) {
        from = found;
        to = found + needle.length;
      }
    }
    // Selecting the range makes the match visible and tells the editor to
    // scroll it into view, which a collapsed caret would not do.
    _controller.selection = TextSelection(
      baseOffset: start + from,
      extentOffset: start + to,
    );
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
        _saved = true;
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
      Navigator.of(context).pop(_saved);
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
    if (leave && mounted) Navigator.of(context).pop(_saved);
  }

  void _openLargeFile() {
    setState(() {
      _forceOpen = true;
      _loading = true;
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final language = languageForPath(widget.path);
    final markdownDark = _markdownDark ?? state.darkMode;
    final name = widget.path.split('/').last;
    final slash = widget.path.lastIndexOf('/');
    final parent = slash < 0 ? 'project root' : widget.path.substring(0, slash);
    return Scaffold(
      backgroundColor: _preview ? Pal.canvas : Pal.ghBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(Sp.x1, Sp.x1, Sp.x2, Sp.x2),
              decoration: BoxDecoration(
                color: Pal.ghPanel,
                border: Border(bottom: BorderSide(color: Pal.ghLine)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconAction(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onTap: _confirmLeave,
                      ),
                      const SizedBox(width: 2),
                      FileGlyph(name: name, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Txt.code.copyWith(
                                      fontSize: 13.5,
                                      height: 1.2,
                                      fontWeight: FontWeight.w600,
                                      color: Pal.ghText,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 7),
                                MonoChip(_typeLabel),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _loading
                                  ? 'reading file…'
                                  : _binary || _image
                                      ? '${humanFileSize(_bytes?.length ?? 0)} · saved on device'
                                      : '$parent · $_lineCount lines',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Txt.meta.copyWith(
                                fontSize: 9.5,
                                color: Pal.ghMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_canEdit) ...[
                        const SizedBox(width: 4),
                        Opacity(
                          opacity: _undo.value.canUndo ? 1 : 0.32,
                          child: IconAction(
                            icon: Icons.undo_rounded,
                            tooltip: 'Undo',
                            size: 17,
                            padding: const EdgeInsets.all(6),
                            onTap: _undo.value.canUndo ? _undo.undo : null,
                          ),
                        ),
                        Opacity(
                          opacity: _undo.value.canRedo ? 1 : 0.32,
                          child: IconAction(
                            icon: Icons.redo_rounded,
                            tooltip: 'Redo',
                            size: 17,
                            padding: const EdgeInsets.all(6),
                            onTap: _undo.value.canRedo ? _undo.redo : null,
                          ),
                        ),
                        IconAction(
                          icon: Icons.search_rounded,
                          tooltip: 'Find in file',
                          size: 18,
                          padding: const EdgeInsets.all(6),
                          onTap: _toggleFind,
                        ),
                        const SizedBox(width: 4),
                        EmberButton(
                          label: _saving ? 'Saving' : 'Save',
                          compact: true,
                          loading: _saving,
                          onTap: _dirty && !_saving ? _save : null,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: _dirty ? Pal.amber : Pal.mint,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _dirty ? 'Unsaved changes' : 'Saved on device',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Txt.meta.copyWith(
                                  fontSize: 9.5,
                                  color: _dirty ? Pal.amber : Pal.textDim,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_preview && _isMarkdown)
                        _MarkdownThemeToggle(
                          dark: markdownDark,
                          onChanged: (dark) =>
                              setState(() => _markdownDark = dark),
                        ),
                      if (_hasPreview)
                        GestureDetector(
                          onTap: _togglePreview,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 5),
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
                                  size: 13,
                                  color: _preview ? Pal.ember : Pal.textMuted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _preview ? 'Code' : 'Preview',
                                  style: Txt.meta.copyWith(
                                    fontSize: 9.5,
                                    color: Pal.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (!_preview && _canEdit) _fontSizeControl(state),
                      if (!_preview && _canEdit)
                        IconAction(
                          icon: state.wordWrap
                              ? Icons.wrap_text_rounded
                              : Icons.notes_rounded,
                          tooltip: state.wordWrap
                              ? 'Disable wrapping'
                              : 'Wrap lines',
                          size: 18,
                          onTap: () => state.setWordWrap(!state.wordWrap),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (_searchOpen && !_preview)
              Container(
                padding: const EdgeInsets.fromLTRB(Sp.x3, 4, Sp.x2, 5),
                decoration: BoxDecoration(
                  color: Pal.ghPanel,
                  border: Border(bottom: BorderSide(color: Pal.ghLine)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _find,
                        focusNode: _findFocus,
                        style: Txt.code.copyWith(fontSize: 11.5),
                        cursorColor: Pal.ember,
                        onChanged: _runFind,
                        onSubmitted: (_) => _selectFind(_findIndex + 1),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Find in file',
                          hintStyle: Txt.meta.copyWith(color: Pal.ghMuted),
                          prefixIcon: Icon(Icons.search_rounded,
                              size: 16, color: Pal.ghMuted),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 30, minHeight: 30),
                          filled: true,
                          fillColor: Pal.raised,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 7),
                          border: const OutlineInputBorder(
                            borderRadius: Rd.sm,
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _findStarts.isEmpty
                          ? '0/0'
                          : '${_findIndex + 1}/${_findStarts.length}',
                      style: Txt.meta.copyWith(fontSize: 9.5),
                    ),
                    IconAction(
                      icon: Icons.keyboard_arrow_up_rounded,
                      tooltip: 'Previous match',
                      size: 18,
                      padding: const EdgeInsets.all(5),
                      onTap: _findStarts.isEmpty
                          ? null
                          : () => _selectFind(_findIndex - 1),
                    ),
                    IconAction(
                      icon: Icons.keyboard_arrow_down_rounded,
                      tooltip: 'Next match',
                      size: 18,
                      padding: const EdgeInsets.all(5),
                      onTap: _findStarts.isEmpty
                          ? null
                          : () => _selectFind(_findIndex + 1),
                    ),
                    IconAction(
                      icon: Icons.close_rounded,
                      tooltip: 'Close find',
                      size: 16,
                      padding: const EdgeInsets.all(5),
                      onTap: _toggleFind,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _content(language, state.wordWrap, markdownDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fontSizeControl(AppState state) {
    final value = state.editorFontSize;
    Widget step(String label, int delta, bool enabled) {
      return Semantics(
        button: true,
        label: delta < 0 ? 'Decrease font size' : 'Increase font size',
        child: GestureDetector(
          onTap: enabled ? () => state.setEditorFontSize(value + delta) : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 28,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? Pal.raised : Pal.raised.withOpacity(0.45),
              borderRadius: Rd.sm,
              border: Border.all(
                color: enabled ? Pal.lineStrong : Pal.line,
              ),
            ),
            child: Text(
              label,
              style: Txt.meta.copyWith(
                fontSize: 10,
                color: enabled ? Pal.text : Pal.textDim,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.pill,
        border: Border.all(color: Pal.lineStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          step('A−', -1, value > 8),
          SizedBox(
            width: 22,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Txt.meta.copyWith(
                fontSize: 9.5,
                color: Pal.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          step('A+', 1, value < 22),
        ],
      ),
    );
  }

  Widget _content(CodeLanguage language, bool wrap, bool markdownDark) {
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
    if (_tooLarge) return _largeFilePreview();
    if (_isMarkdown && _preview) {
      return GithubMarkdownPreview(
        project: widget.project,
        path: widget.path,
        source: _controller.text,
        dark: markdownDark,
      );
    }
    return CodeEditor(
      controller: _controller,
      language: language,
      wrap: wrap,
      fontSize: AppScope.of(context).editorFontSize.toDouble(),
      undoController: _undo,
      findStarts: _findStarts,
      findEnds: _findEnds,
      activeFindIndex: _findIndex,
      onChanged: (_) {
        if (!_dirty) setState(() => _dirty = true);
      },
    );
  }

  Widget _largeFilePreview() {
    return ListView(
      padding: const EdgeInsets.all(Sp.page),
      children: [
        EmptyState(
          icon: Icons.data_array_rounded,
          title: 'Large file',
          body: '${widget.path} is ${humanFileSize(_bytes?.length ?? 0)}. '
              'Loading all of it at once can make the workspace slow on this '
              'device. Open it only if you need to edit the whole file.',
        ),
        const SizedBox(height: Sp.x4),
        EmberButton(
          label: 'Open anyway',
          icon: Icons.open_in_full_rounded,
          onTap: _openLargeFile,
        ),
        const SizedBox(height: Sp.x3),
        Text(
          'Opening a large file as text turns off syntax highlighting above '
          '160 KB, but the full contents still load into the editor.',
          style: Txt.meta,
        ),
      ],
    );
  }

  Widget _imagePreview() {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.shrink();
    return Container(
      color: Pal.canvas,
      padding: const EdgeInsets.all(Sp.x4),
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: SizedBox.expand(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Text(
                'This image format cannot be rendered on this device.\n'
                'The file is intact and will still be committed byte for byte.',
                textAlign: TextAlign.center,
                style: Txt.bodySoft,
              ),
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
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: SizedBox.expand(
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

class _MarkdownThemeToggle extends StatelessWidget {
  const _MarkdownThemeToggle({
    required this.dark,
    required this.onChanged,
  });

  final bool dark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.pill,
        border: Border.all(color: Pal.lineStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _option(
            icon: Icons.light_mode_outlined,
            label: 'Light preview',
            selected: !dark,
            onTap: () => onChanged(false),
          ),
          _option(
            icon: Icons.dark_mode_outlined,
            label: 'Dark preview',
            selected: dark,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _option({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: selected ? null : onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: Motion.fast,
            width: 28,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  selected ? Pal.ember.withOpacity(0.14) : Colors.transparent,
              borderRadius: Rd.pill,
            ),
            child: Icon(
              icon,
              size: 14,
              color: selected ? Pal.ember : Pal.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
