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
    scan(
      RegExp(r'\b(?:' + keywords.join('|') + r')\b'),
      Pal.ghKeyword,
    );
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
      scan(RegExp(r'''"[^"\n]*"'''), Pal.ghString);
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

/// A [TextEditingController] that paints GitHub-dark syntax colours while
/// staying fully editable.
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

class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    required this.controller,
    required this.language,
    required this.onChanged,
    this.wrap = false,
  });

  final CodeController controller;
  final CodeLanguage language;
  final ValueChanged<String> onChanged;
  final bool wrap;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final _scroll = ScrollController();
  double _offset = 0;
  bool _wired = false;

  static const _fontSize = 12.5;
  static const _lineHeight = 1.62;
  static const _padding = 14.0;

  double get _rowHeight => _fontSize * _lineHeight;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant CodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    if ((_scroll.offset - _offset).abs() < 0.5) return;
    setState(() => _offset = _scroll.offset);
  }

  void _onText() {
    if (!mounted) return;
    if (!_wired) _wired = true;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.controller.text.split('\n').length;
    final showGutter = !widget.wrap && lines <= 1500;

    return Container(
      color: Pal.ghBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showGutter)
            Container(
              width: 46,
              decoration: const BoxDecoration(
                color: Pal.ghPanel,
                border: Border(right: BorderSide(color: Pal.ghLine)),
              ),
              child: ClipRect(
                child: Padding(
                  padding: const EdgeInsets.only(top: _padding),
                  child: Stack(
                    children: [
                      Transform.translate(
                        offset: Offset(0, -_offset),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 1; i <= lines; i++)
                              SizedBox(
                                height: _rowHeight,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Text(
                                    '$i',
                                    textAlign: TextAlign.right,
                                    style: Txt.meta.copyWith(
                                      fontSize: 10.5,
                                      height: 1,
                                      color: Pal.ghMuted,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              scrollController: _scroll,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: Txt.code.copyWith(
                fontSize: _fontSize,
                height: _lineHeight,
                color: Pal.ghText,
              ),
              cursorColor: Pal.ember,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.multiline,
              onChanged: widget.onChanged,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(_padding, _padding, 10, 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
