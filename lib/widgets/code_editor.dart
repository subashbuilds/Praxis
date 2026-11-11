import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum CodeLanguage {
  html,
  css,
  javascript,
  dart,
  python,
  json,
  markdown,
  yaml,
  text
}

CodeLanguage languageForPath(String path) {
  final name = path.split('/').last.toLowerCase();
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1);
  return switch (ext) {
    'html' || 'htm' => CodeLanguage.html,
    'css' || 'scss' || 'less' => CodeLanguage.css,
    'js' || 'jsx' || 'ts' || 'tsx' => CodeLanguage.javascript,
    'dart' => CodeLanguage.dart,
    'py' => CodeLanguage.python,
    'json' => CodeLanguage.json,
    'md' || 'markdown' => CodeLanguage.markdown,
    'yaml' || 'yml' => CodeLanguage.yaml,
    _ => CodeLanguage.text,
  };
}

extension CodeLanguageLabel on CodeLanguage {
  String get label => switch (this) {
        CodeLanguage.html => 'HTML',
        CodeLanguage.css => 'CSS',
        CodeLanguage.javascript => 'JavaScript',
        CodeLanguage.dart => 'Dart',
        CodeLanguage.python => 'Python',
        CodeLanguage.json => 'JSON',
        CodeLanguage.markdown => 'Markdown',
        CodeLanguage.yaml => 'YAML',
        CodeLanguage.text => 'Text',
      };
}

class _Token {
  const _Token(this.start, this.end, this.color);
  final int start;
  final int end;
  final Color color;
}

const _keywords = <CodeLanguage, Set<String>>{
  CodeLanguage.javascript: {
    'const',
    'let',
    'var',
    'function',
    'return',
    'if',
    'else',
    'for',
    'while',
    'do',
    'switch',
    'case',
    'break',
    'continue',
    'class',
    'extends',
    'new',
    'this',
    'super',
    'import',
    'export',
    'from',
    'async',
    'await',
    'try',
    'catch',
    'finally',
    'throw',
    'typeof',
    'instanceof',
    'in',
    'of',
    'null',
    'undefined',
    'true',
    'false',
    'interface',
    'type',
    'enum',
    'implements',
    'public',
    'private',
    'static',
    'default',
    'yield',
    'delete',
    'void',
  },
  CodeLanguage.dart: {
    'abstract',
    'as',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'if',
    'implements',
    'import',
    'in',
    'is',
    'late',
    'new',
    'null',
    'on',
    'required',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'var',
    'void',
    'while',
    'with',
    'yield',
    'static',
  },
  CodeLanguage.python: {
    'and',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'class',
    'continue',
    'def',
    'del',
    'elif',
    'else',
    'except',
    'False',
    'finally',
    'for',
    'from',
    'global',
    'if',
    'import',
    'in',
    'is',
    'lambda',
    'None',
    'nonlocal',
    'not',
    'or',
    'pass',
    'raise',
    'return',
    'True',
    'try',
    'while',
    'with',
    'yield',
  },
  CodeLanguage.json: {'true', 'false', 'null'},
  CodeLanguage.yaml: {'true', 'false', 'null', 'yes', 'no'},
};

List<InlineSpan> _highlight(String text, CodeLanguage language) {
  // Highlighting a very large file means thousands of spans on every frame.
  // Plain text stays editable and scrolls smoothly instead.
  if (text.length > 160000) return [TextSpan(text: text)];
  if (text.isEmpty || language == CodeLanguage.text) {
    return [TextSpan(text: text)];
  }
  final tokens = <_Token>[];
  void scan(RegExp pattern, Color color) {
    for (final match in pattern.allMatches(text)) {
      if (match.end > match.start) {
        tokens.add(_Token(match.start, match.end, color));
      }
    }
  }

  final keywords = _keywords[language];
  if (keywords != null && keywords.isNotEmpty) {
    scan(RegExp(r'\b(?:' + keywords.join('|') + r')\b'), Pal.ghKeyword);
  }

  switch (language) {
    case CodeLanguage.html:
      scan(RegExp(r'<!--[\s\S]*?-->'), Pal.ghMuted);
      scan(RegExp(r'(?<=</)[a-zA-Z][\w-]*'), Pal.ghTag);
      scan(RegExp(r'(?<=<)[a-zA-Z][\w-]*'), Pal.ghTag);
      scan(RegExp(r'\b[a-zA-Z-]+(?=\s*=)'), Pal.ghAttr);
      scan(RegExp(r'"[^"]*"'), Pal.ghString);
      scan(RegExp(r"'[^']*'"), Pal.ghString);
    case CodeLanguage.css:
      scan(RegExp(r'/\*[\s\S]*?\*/'), Pal.ghMuted);
      scan(RegExp(r'"[^"]*"'), Pal.ghString);
      scan(RegExp(r"'[^']*'"), Pal.ghString);
      scan(RegExp(r'#[0-9a-fA-F]{3,8}\b'), Pal.ghNumber);
      scan(RegExp(r'\b[a-zA-Z-]+(?=\s*:)'), Pal.ghAttr);
      scan(RegExp(r'\b\d+(?:\.\d+)?(?:px|rem|em|%|vh|vw|s|ms)?\b'),
          Pal.ghNumber);
    case CodeLanguage.javascript:
    case CodeLanguage.dart:
    case CodeLanguage.python:
      scan(
        language == CodeLanguage.python
            ? RegExp(r'#[^\n]*')
            : RegExp(r'//[^\n]*|/\*[\s\S]*?\*/'),
        Pal.ghMuted,
      );
      scan(RegExp(r'''"[^"\n]*"|'[^'\n]*'|`[^`]*`'''), Pal.ghString);
      scan(RegExp(r'\b\d+(?:\.\d+)?\b'), Pal.ghNumber);
      scan(RegExp(r'\b[A-Za-z_]\w*(?=\s*\()'), Pal.ghAttr);
    case CodeLanguage.json:
      scan(RegExp(r'"[^"\n]*"'), Pal.ghString);
      scan(RegExp(r'\b-?\d+(?:\.\d+)?\b'), Pal.ghNumber);
    case CodeLanguage.markdown:
      scan(RegExp(r'^#{1,6} .*$', multiLine: true), Pal.ghNumber);
      scan(RegExp(r'```[\s\S]*?```'), Pal.ghString);
      scan(RegExp(r'\*\*[^*\n]+\*\*'), Pal.ghTag);
      scan(RegExp(r'`[^`\n]+`'), Pal.ghAttr);
      scan(RegExp(r'\[[^\]\n]+\]\([^)\n]+\)'), Pal.ghAttr);
    case CodeLanguage.yaml:
      scan(RegExp(r'#[^\n]*'), Pal.ghMuted);
      scan(RegExp(r'''"[^"\n]*"|'[^'\n]*' '''), Pal.ghString);
      scan(RegExp(r'^\s*[A-Za-z_][\w-]*(?=\s*:)', multiLine: true), Pal.ghAttr);
      scan(RegExp(r'\b\d+(?:\.\d+)?\b'), Pal.ghNumber);
    case CodeLanguage.text:
      break;
  }

  tokens.sort((a, b) {
    if (a.start != b.start) return a.start - b.start;
    return b.end.compareTo(a.end);
  });
  final chosen = <_Token>[];
  var covered = 0;
  for (final token in tokens) {
    if (token.start < covered) continue;
    chosen.add(token);
    covered = token.end;
  }

  final spans = <InlineSpan>[];
  var at = 0;
  for (final token in chosen) {
    if (token.start > at) {
      spans.add(TextSpan(text: text.substring(at, token.start)));
    }
    spans.add(TextSpan(
      text: text.substring(token.start, token.end),
      style: TextStyle(color: token.color),
    ));
    at = token.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// A [TextEditingController] that paints GitHub syntax colours while staying
/// fully editable.
class CodeController extends TextEditingController {
  CodeController({required this.language});

  CodeLanguage language;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    return TextSpan(style: base, children: _highlight(value.text, language));
  }
}

/// A code editor whose gutter is laid out from the same metrics as the text.
/// Wrapping is a real preference: when it is off the code scrolls horizontally
/// and every logical line keeps exactly one number.
class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    required this.controller,
    required this.language,
    required this.onChanged,
    this.wrap = false,
    this.fontSize = 12.5,
    this.undoController,
    this.findStarts = const [],
    this.findEnds = const [],
    this.activeFindIndex = 0,
  });

  final CodeController controller;
  final CodeLanguage language;
  final ValueChanged<String> onChanged;
  final bool wrap;
  final double fontSize;
  final UndoHistoryController? undoController;

  /// All find matches. They are painted behind the text so every occurrence is
  /// visible at once; [activeFindIndex] is drawn in a stronger colour.
  final List<int> findStarts;
  final List<int> findEnds;
  final int activeFindIndex;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  final _focus = FocusNode();

  static const _gutter = 46.0;
  static const _lineHeight = 1.5;
  static const _top = 14.0;
  static const _bottom = 40.0;
  static const _left = 14.0;
  static const _right = 16.0;
  double get _fontSize => widget.fontSize;
  double get _row => _fontSize * _lineHeight;

  List<double> _lineHeights = const [];
  double _viewportWidth = 0;
  List<Rect> _findMatches = const [];
  List<Rect> _findActive = const [];
  String _findCacheText = '';
  double _findCacheWidth = -1;
  int _findCacheSignature = -1;

  TextStyle get _style => Txt.code.copyWith(
        fontSize: _fontSize,
        height: _lineHeight,
        color: Pal.ghText,
        letterSpacing: 0,
      );

  StrutStyle get _strut => StrutStyle(
        fontFamily: Txt.mono,
        fontSize: _fontSize,
        height: _lineHeight,
        forceStrutHeight: true,
      );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant CodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
    if (oldWidget.wrap != widget.wrap ||
        oldWidget.fontSize != widget.fontSize) {
      _lineHeights = const [];
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _vertical.dispose();
    _horizontal.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // A programmatic selection (find, or jumping to a search result) must
    // scroll even though the text field does not own focus.
    final jumped = !widget.controller.selection.isCollapsed;
    if (!_focus.hasFocus && !jumped) return;
    _lineHeights = const [];
    setState(() {});
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _revealCaret(force: jumped));
  }

  void _revealCaret({bool force = false}) {
    if (!mounted || (!force && !_focus.hasFocus)) return;
    final selection = widget.controller.selection;
    if (!selection.isValid) return;
    final text = widget.controller.text;
    final offset = selection.baseOffset.clamp(0, text.length);
    final lineStart = text.lastIndexOf('\n', offset - 1) + 1;
    final lineEnd = text.indexOf('\n', offset);
    final lineText = text.substring(
      lineStart,
      lineEnd < 0 ? text.length : lineEnd,
    );
    final lineIndex = '\n'.allMatches(text.substring(0, lineStart)).length;
    final heights = _lineHeights;
    if (heights.isEmpty || lineIndex >= heights.length) return;

    var top = 0.0;
    for (var i = 0; i < lineIndex; i++) {
      top += heights[i];
    }
    final caretLineHeight = heights[lineIndex];
    if (_vertical.hasClients) {
      final viewport = _vertical.position.viewportDimension;
      final target = _top + top;
      if (target < _vertical.offset + 12) {
        _vertical.jumpTo(math.max(0, target - _top - 12));
      } else if (target + caretLineHeight > _vertical.offset + viewport - 28) {
        _vertical.jumpTo(math.min(_vertical.position.maxScrollExtent,
            target + caretLineHeight - viewport + 40));
      }
    }

    if (!widget.wrap && _horizontal.hasClients) {
      final before = lineText.substring(
        0,
        (offset - lineStart).clamp(0, lineText.length),
      );
      final painter = TextPainter(
        text: TextSpan(text: before, style: _style),
        textDirection: TextDirection.ltr,
        strutStyle: _strut,
      )..layout();
      final caret = _left + painter.width;
      final viewport = _horizontal.position.viewportDimension;
      if (caret < _horizontal.offset + 12) {
        _horizontal.jumpTo(math.max(0, caret - 40));
      } else if (caret > _horizontal.offset + viewport - 24) {
        _horizontal.jumpTo(math.min(
          _horizontal.position.maxScrollExtent,
          caret - viewport + 48,
        ));
      }
    }
  }

  double _longestLineWidth(String text) {
    var max = 0.0;
    for (final line in text.split('\n')) {
      final painter = TextPainter(
        text: TextSpan(text: line.isEmpty ? ' ' : line, style: _style),
        textDirection: TextDirection.ltr,
        strutStyle: _strut,
      )..layout();
      max = math.max(max, painter.width);
    }
    return max;
  }

  List<double> _measure(String text, double width) {
    if (!widget.wrap) {
      final count = text.split('\n').length;
      return List<double>.filled(count, _row);
    }
    return [
      for (final line in text.split('\n'))
        () {
          final painter = TextPainter(
            text: TextSpan(text: line.isEmpty ? ' ' : line, style: _style),
            textDirection: TextDirection.ltr,
            strutStyle: _strut,
          )..layout(maxWidth: math.max(20, width));
          final rows = math.max(1, (painter.height / _row).ceil());
          return rows * _row;
        }(),
    ];
  }

  /// One text run, using exactly the same strut as the editor. A Column of
  /// smaller Text widgets gave each number a different baseline and wrapped
  /// lines drifted away from their numbers; a single run keeps the metrics
  /// identical. Blank lines reserve the extra visual rows of a wrapped line.
  String _gutterText(List<double> heights) {
    final buffer = StringBuffer();
    for (var i = 0; i < heights.length; i++) {
      if (i > 0) buffer.write('\n');
      buffer.write(i + 1);
      if (widget.wrap) {
        final rows = math.max(1, (heights[i] / _row).round());
        for (var row = 1; row < rows; row++) {
          buffer.write('\n');
        }
      }
    }
    return buffer.toString();
  }

  void _layoutFindHighlights(String text, double width, TextScaler scaler) {
    if (widget.findStarts.isEmpty) {
      _findMatches = const [];
      _findActive = const [];
      _findCacheText = text;
      _findCacheWidth = width;
      _findCacheSignature = -1;
      return;
    }
    final signature = Object.hash(
      widget.findStarts.length,
      widget.findEnds.length,
      widget.activeFindIndex,
      text.length,
      scaler,
    );
    if (_findCacheText == text &&
        _findCacheWidth == width &&
        _findCacheSignature == signature) {
      return;
    }
    _findCacheText = text;
    _findCacheWidth = width;
    _findCacheSignature = signature;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _style),
      textDirection: TextDirection.ltr,
      strutStyle: _strut,
      textScaler: scaler,
    )..layout(maxWidth: width);
    final matches = <Rect>[];
    final active = <Rect>[];
    final count = math.min(widget.findStarts.length, 600);
    for (var index = 0; index < count; index++) {
      final start = widget.findStarts[index].clamp(0, text.length);
      final end = widget.findEnds[index].clamp(start, text.length);
      for (final box in painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      )) {
        final rect = Rect.fromLTWH(
          box.left + _left,
          box.top + _top,
          math.max(1, box.right - box.left),
          box.bottom - box.top,
        );
        if (index == widget.activeFindIndex) {
          active.add(rect);
        } else {
          matches.add(rect);
        }
      }
    }
    painter.dispose();
    _findMatches = matches;
    _findActive = active;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = widget.controller.text;
        final codeViewport =
            math.max(80.0, constraints.maxWidth - _gutter - _left - _right);
        if (_viewportWidth != codeViewport) {
          _viewportWidth = codeViewport;
          _lineHeights = const [];
        }
        final codeWidth = widget.wrap
            ? codeViewport
            : math.max(codeViewport, _longestLineWidth(text) + 18);
        final heights = _lineHeights.isNotEmpty && widget.wrap
            ? _lineHeights
            : _measure(text, codeWidth);
        _lineHeights = heights;
        final total = _top +
            heights.fold<double>(0, (sum, value) => sum + value) +
            _bottom;

        final gutter = Container(
          width: _gutter,
          color: Pal.ghPanel,
          padding: const EdgeInsets.only(top: _top, right: 9),
          child: Text(
            _gutterText(heights),
            textAlign: TextAlign.right,
            softWrap: false,
            style: _style.copyWith(color: Pal.ghMuted),
            strutStyle: _strut,
          ),
        );

        _layoutFindHighlights(
          text,
          codeWidth,
          MediaQuery.textScalerOf(context),
        );
        final field = TextField(
          controller: widget.controller,
          undoController: widget.undoController,
          focusNode: _focus,
          maxLines: null,
          minLines: null,
          expands: false,
          scrollPhysics: const NeverScrollableScrollPhysics(),
          textAlignVertical: TextAlignVertical.top,
          style: _style,
          strutStyle: _strut,
          cursorColor: Pal.ember,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          onChanged: widget.onChanged,
          decoration: const InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.fromLTRB(_left, _top, _right, _bottom),
          ),
        );
        final editor = Stack(
          children: [
            if (_findMatches.isNotEmpty || _findActive.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _FindHighlightPainter(
                      matches: _findMatches,
                      active: _findActive,
                    ),
                  ),
                ),
              ),
            field,
          ],
        );

        return Container(
          color: Pal.ghBg,
          // The gutter is inside the same vertical scroll surface as the code.
          // Keeping it in a separate column made line numbers look frozen while
          // the text scrolled underneath them.
          child: Scrollbar(
            controller: _vertical,
            child: SingleChildScrollView(
              controller: _vertical,
              padding: EdgeInsets.zero,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  gutter,
                  Container(width: 1, height: total, color: Pal.ghLine),
                  Expanded(
                    child: widget.wrap
                        ? SizedBox(
                            width: codeViewport + _left + _right,
                            child: editor,
                          )
                        : Scrollbar(
                            controller: _horizontal,
                            notificationPredicate: (notification) =>
                                notification.metrics.axis == Axis.horizontal,
                            child: SingleChildScrollView(
                              controller: _horizontal,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: codeWidth + _left + _right,
                                child: editor,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints find matches behind the editor text. The field itself stays the only
/// text renderer, so selection, IME and scrolling keep working as usual.
class _FindHighlightPainter extends CustomPainter {
  const _FindHighlightPainter({required this.matches, required this.active});

  final List<Rect> matches;
  final List<Rect> active;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Pal.amber.withOpacity(0.22);
    for (final rect in matches) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
    }
    paint.color = Pal.ember.withOpacity(0.42);
    for (final rect in active) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FindHighlightPainter oldDelegate) =>
      oldDelegate.matches != matches || oldDelegate.active != active;
}
