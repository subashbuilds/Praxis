import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'code_editor.dart';
import 'ui.dart';

/// Renders an agent reply the way it was written: fenced code becomes a
/// highlighted block, inline `code` keeps its monospace chip, and headings and
/// lists keep their shape instead of showing their Markdown markers.
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Txt.body.copyWith(height: 1.58);
    final blocks = _parse(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          if (index > 0) const SizedBox(height: 4),
          blocks[index].build(context, base),
        ],
      ],
    );
  }
}

abstract class _Block {
  Widget build(BuildContext context, TextStyle base);
}

class _TextBlock extends _Block {
  _TextBlock(this.text);

  final String text;

  @override
  Widget build(BuildContext context, TextStyle base) {
    final children = <Widget>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 7));
        continue;
      }
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 6, bottom: 2),
          child: Text.rich(
            TextSpan(
              children: _inline(
                heading.group(2)!,
                base.copyWith(
                  fontSize: level <= 2 ? 15.5 : 14.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
            style: base.copyWith(
              fontSize: level <= 2 ? 15.5 : 14.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ));
        continue;
      }
      final bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text('•', style: base.copyWith(color: Pal.textDim)),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text.rich(
                  TextSpan(children: _inline(bullet.group(2)!, base)),
                  style: base,
                ),
              ),
            ],
          ),
        ));
        continue;
      }
      children.add(Text.rich(
        TextSpan(children: _inline(line, base)),
        style: base,
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _CodeBlock extends _Block {
  _CodeBlock({required this.label, required this.code});

  final String label;
  final String code;

  @override
  Widget build(BuildContext context, TextStyle base) {
    final language = languageForFence(label);
    final header = language == CodeLanguage.text
        ? (label.isEmpty ? 'CODE' : label.toUpperCase())
        : language.label;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 2, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    header,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.overline.copyWith(
                      fontSize: 8.5,
                      color: Pal.textDim,
                    ),
                  ),
                ),
                IconAction(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy code',
                  size: 14,
                  padding: const EdgeInsets.all(7),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied.')),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text.rich(
                TextSpan(
                  style: Txt.code.copyWith(
                    fontSize: 12,
                    height: 1.5,
                    color: Pal.text,
                  ),
                  children: highlightCodeSpans(code, language),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<_Block> _parse(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_Block>[];
  final paragraph = <String>[];

  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(_TextBlock(paragraph.join('\n')));
    paragraph.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fence =
        RegExp(r'^\s*```+\s*([A-Za-z0-9_+#.-]*)\s*$').firstMatch(line);
    if (fence != null) {
      flush();
      final code = <String>[];
      i++;
      while (i < lines.length && !RegExp(r'^\s*```+\s*$').hasMatch(lines[i])) {
        code.add(lines[i]);
        i++;
      }
      blocks
          .add(_CodeBlock(label: fence.group(1) ?? '', code: code.join('\n')));
      continue;
    }
    paragraph.add(line);
  }
  flush();
  return blocks;
}

List<InlineSpan> _inline(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'(`[^`\n]+`|\*\*[^*\n]+\*\*)');
  var at = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > at) {
      spans.add(TextSpan(text: text.substring(at, match.start)));
    }
    final value = match.group(0)!;
    if (value.startsWith('`')) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Pal.overlay,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Pal.line),
          ),
          child: Text(
            value.substring(1, value.length - 1),
            style: Txt.code.copyWith(fontSize: 12, color: Pal.text),
          ),
        ),
      ));
    } else {
      spans.add(TextSpan(
        text: value.substring(2, value.length - 2),
        style: base.copyWith(fontWeight: FontWeight.w700),
      ));
    }
    at = match.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}
