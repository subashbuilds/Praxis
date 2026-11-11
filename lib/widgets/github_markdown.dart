import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:webview_flutter/webview_flutter.dart';

import '../core/readme_html.dart';
import '../models.dart';
import '../state/app_state.dart';

/// Renders a README the way GitHub does: the Markdown is converted to HTML and
/// shown in a WebView with GitHub's document CSS. That also keeps raw README
/// HTML such as `<p align="center">`, badge links and `<details>` blocks.
class GithubMarkdownPreview extends StatefulWidget {
  const GithubMarkdownPreview({
    super.key,
    required this.project,
    required this.path,
    required this.source,
    required this.dark,
  });

  final Project project;
  final String path;
  final String source;
  final bool dark;

  @override
  State<GithubMarkdownPreview> createState() => _GithubMarkdownPreviewState();
}

class _GithubMarkdownPreviewState extends State<GithubMarkdownPreview> {
  static const _lightCanvas = Color(0xFFFFFFFF);
  static const _darkCanvas = Color(0xFF0D1117);
  static const _lightText = Color(0xFF1F2328);
  static const _darkText = Color(0xFFE6EDF3);

  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.disabled)
    ..setBackgroundColor(_lightCanvas)
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (request.url.startsWith('about:')) {
            return NavigationDecision.navigate;
          }
          Clipboard.setData(ClipboardData(text: request.url));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Link copied: ${request.url}')),
          );
          return NavigationDecision.prevent;
        },
      ),
    );
  String? _lastKey;
  String? _body;
  bool _loading = true;
  bool _started = false;
  int _documentToken = 0;

  Color get _canvas => widget.dark ? _darkCanvas : _lightCanvas;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _controller.setBackgroundColor(_canvas);
    _render();
  }

  @override
  void didUpdateWidget(covariant GithubMarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = oldWidget.source != widget.source ||
        oldWidget.path != widget.path ||
        oldWidget.project.id != widget.project.id;
    if (sourceChanged) {
      _render();
    } else if (oldWidget.dark != widget.dark) {
      _loadDocument();
    }
  }

  Future<void> _render() async {
    final key = '${widget.project.id}|${widget.path}|${widget.source}';
    _lastKey = key;
    _documentToken++;
    if (mounted) setState(() => _loading = true);
    final body = await _readmeBody(
      widget.source,
      readmePath: widget.path,
      loadLocal: (uri) async {
        final relative = resolveReadmeImagePath(widget.path, uri);
        if (relative.isEmpty) return null;
        try {
          return await AppScope.of(context)
              .readFileBytes(widget.project, relative);
        } catch (_) {
          return null;
        }
      },
    );
    if (!mounted || _lastKey != key) return;
    _body = body;
    await _loadDocument();
  }

  Future<void> _loadDocument() async {
    final body = _body;
    if (body == null) return;
    final token = ++_documentToken;
    await _controller.setBackgroundColor(_canvas);
    await _controller.loadHtmlString(
      _readmeDocument(body, dark: widget.dark),
    );
    if (!mounted || token != _documentToken) return;
    if (_loading) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.dark ? _darkText : _lightText,
              ),
            ),
          ),
      ],
    );
  }
}

Future<String> _readmeBody(
  String source, {
  required String readmePath,
  required Future<Uint8List?> Function(Uri) loadLocal,
}) async {
  var body = md.markdownToHtml(
    source.isEmpty ? '_This file is empty._' : source,
    extensionSet: md.ExtensionSet.gitHubWeb,
    encodeHtml: false,
  );
  final image = RegExp(
    r'''<img\b[^>]*\bsrc\s*=\s*("([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  );
  final matches = image.allMatches(body).toList();
  for (final match in matches.reversed) {
    final raw = match.group(2) ?? match.group(3) ?? '';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.hasScheme || uri.hasAuthority) continue;
    if (resolveReadmeImagePath(readmePath, uri).isEmpty) continue;
    final bytes = await loadLocal(uri);
    if (bytes == null || bytes.isEmpty) continue;
    final extension = uri.path.toLowerCase().split('.').last;
    final mime = switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      _ => 'application/octet-stream',
    };
    final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';
    final srcStart = match.start + match.group(0)!.indexOf(raw);
    final srcEnd = srcStart + raw.length;
    body = body.replaceRange(srcStart, srcEnd, dataUri);
  }
  return body;
}

String _readmeDocument(String body, {required bool dark}) {
  return '''<!doctype html>
<html data-theme="${dark ? 'dark' : 'light'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=3">
<style>
:root {
  color-scheme: light;
  --bg: #ffffff;
  --fg: #1f2328;
  --muted: #59636e;
  --line: #d1d9e0;
  --link: #0969da;
  --code-bg: #f6f8fa;
  --inline-code-bg: rgba(129, 139, 152, .12);
  --stripe: #f6f8fa;
  --kbd-shadow: inset 0 -1px 0 #d1d9e0;
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --bg: #0d1117;
  --fg: #e6edf3;
  --muted: #8b949e;
  --line: #30363d;
  --link: #4493f8;
  --code-bg: #151b23;
  --inline-code-bg: rgba(101, 108, 118, .4);
  --stripe: #151b23;
  --kbd-shadow: inset 0 -1px 0 #30363d;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: var(--bg); }
body {
  color: var(--fg);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
  font-size: 16px;
  line-height: 1.5;
  word-wrap: break-word;
  -webkit-text-size-adjust: 100%;
}
.markdown-body { max-width: 980px; margin: 0 auto; padding: 32px; }
.markdown-body > :first-child { margin-top: 0 !important; }
.markdown-body > :last-child { margin-bottom: 0 !important; }
h1, h2, h3, h4, h5, h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--line); }
h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--line); }
h3 { font-size: 1.25em; }
h4 { font-size: 1em; }
h5 { font-size: .875em; }
h6 { font-size: .85em; color: var(--muted); }
p { margin-top: 0; margin-bottom: 16px; }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
img { max-width: 100%; box-sizing: content-box; border-style: none; vertical-align: middle; }
p > a > img, p > img { margin: 0 2px; }
strong { font-weight: 600; }
hr { height: .25em; padding: 0; margin: 24px 0; background-color: var(--line); border: 0; }
blockquote { margin: 0 0 16px; padding: 0 1em; color: var(--muted); border-left: .25em solid var(--line); }
ul, ol { margin-top: 0; margin-bottom: 16px; padding-left: 2em; }
li + li { margin-top: .25em; }
li > p { margin-top: 16px; }
code, pre, kbd, samp { font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace; }
code { padding: .2em .4em; margin: 0; font-size: 85%; background: var(--inline-code-bg); border-radius: 6px; }
pre { margin-top: 0; margin-bottom: 16px; padding: 16px; overflow: auto; font-size: 85%; line-height: 1.45; background: var(--code-bg); border-radius: 6px; }
pre code { padding: 0; margin: 0; font-size: 100%; background: transparent; border: 0; }
table { display: block; width: max-content; max-width: 100%; overflow: auto; margin-top: 0; margin-bottom: 16px; border-spacing: 0; border-collapse: collapse; }
table th { font-weight: 600; }
table th, table td { padding: 6px 13px; border: 1px solid var(--line); }
table tr:nth-child(2n) { background-color: var(--stripe); }
input[type=checkbox] { margin: 0 .2em .25em -1.4em; vertical-align: middle; }
details { margin-bottom: 16px; }
summary { cursor: pointer; }
kbd { display: inline-block; padding: 3px 5px; font-size: 11px; line-height: 10px; color: var(--fg); vertical-align: middle; background-color: var(--code-bg); border: 1px solid var(--line); border-radius: 6px; box-shadow: var(--kbd-shadow); }
[align="center"], [align="middle"] { text-align: center; }
</style>
</head>
<body>
<article class="markdown-body">
$body
</article>
</body>
</html>''';
}
