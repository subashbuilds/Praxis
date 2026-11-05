/// flutter_markdown intentionally does not render raw HTML. Many READMEs open
/// with centred HTML headings and badge images, so those lines would silently
/// disappear. This converts the small, safe HTML subset commonly found in
/// READMEs to Markdown while leaving fenced code blocks alone.
String markdownFromReadme(String source) {
  final output = StringBuffer();
  var fenced = false;
  String? fence;
  for (final line in source.split('\n')) {
    final trimmed = line.trimLeft();
    final fenceMatch = RegExp(r'^(```+|~~~+)').firstMatch(trimmed);
    if (fenceMatch != null) {
      final marker = fenceMatch.group(1)!;
      if (!fenced) {
        fenced = true;
        fence = marker.substring(0, 1);
      } else if (marker.startsWith(fence!)) {
        fenced = false;
        fence = null;
      }
      output.writeln(line);
      continue;
    }
    output.writeln(fenced ? line : _convertLine(line));
  }
  return output.toString();
}

String _convertLine(String line) {
  if (!line.contains('<')) return _entities(line);
  var value = line;
  value = value.replaceAllMapped(
    RegExp(r'<h([1-6])\b[^>]*>([\s\S]*?)</h\1>', caseSensitive: false),
    (match) =>
        '\n${'#' * int.parse(match.group(1)!)} ${match.group(2)!.trim()}\n',
  );
  value = value.replaceAllMapped(
    RegExp(r'<img\b([^>]*)>', caseSensitive: false),
    (match) {
      final attrs = match.group(1) ?? '';
      final src = _attribute(attrs, 'src');
      if (src.isEmpty) return '';
      final alt = _attribute(attrs, 'alt');
      return '![${_escapeAlt(alt)}]($src)';
    },
  );
  value = value.replaceAllMapped(
    RegExp(r'<a\b([^>]*)>([\s\S]*?)</a>', caseSensitive: false),
    (match) {
      final href = _attribute(match.group(1) ?? '', 'href');
      final label =
          match.group(2)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
      if (href.isEmpty || label.isEmpty) return label;
      return '[$label]($href)';
    },
  );
  value = value.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '  \n');
  value =
      value.replaceAll(RegExp(r'<hr\s*/?>', caseSensitive: false), '\n---\n');
  value = value.replaceAll(
      RegExp(r'<(b|strong)\b[^>]*>', caseSensitive: false), '**');
  value =
      value.replaceAll(RegExp(r'</(b|strong)>', caseSensitive: false), '**');
  value =
      value.replaceAll(RegExp(r'<(i|em)\b[^>]*>', caseSensitive: false), '*');
  value = value.replaceAll(RegExp(r'</(i|em)>', caseSensitive: false), '*');
  value = value.replaceAll(RegExp(r'<code\b[^>]*>', caseSensitive: false), '`');
  value = value.replaceAll(RegExp(r'</code>', caseSensitive: false), '`');
  value = value.replaceAll(
      RegExp(
          r'</?(p|div|center|details|summary|table|thead|tbody|tr|ul|ol)\b[^>]*>',
          caseSensitive: false),
      '\n');
  value = value.replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '- ');
  value = value.replaceAll(RegExp(r'</li>', caseSensitive: false), '\n');
  value = value.replaceAll(RegExp(r'<[^>]+>'), '');
  return _entities(value);
}

String _attribute(String attrs, String name) {
  final match = RegExp(
    '$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(attrs);
  if (match == null) return '';
  return _entities(match.group(1) ?? match.group(2) ?? match.group(3) ?? '');
}

String _escapeAlt(String value) =>
    value.replaceAll('[', '\\[').replaceAll(']', '\\]').replaceAll('\n', ' ');

String _entities(String value) => value
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'");
