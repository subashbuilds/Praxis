import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/common.dart';

class CodeScreen extends StatelessWidget {
  const CodeScreen({super.key, required this.path, required this.code});

  final String path;
  final String code;

  static final _token = RegExp(
    r'''(\/\/[^\n]*)|('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")|\b(abstract|as|async|await|break|case|catch|class|const|continue|default|do|else|enum|extends|final|finally|for|if|implements|import|in|is|late|mixin|new|null|on|required|return|sealed|static|super|switch|this|throw|try|var|void|while|with)\b|\b(\d+(?:\.\d+)?)\b|(@[a-zA-Z_]+)''',
  );

  List<TextSpan> _highlight(String line) {
    final spans = <TextSpan>[];
    var index = 0;
    for (final match in _token.allMatches(line)) {
      if (match.start > index) {
        spans.add(TextSpan(text: line.substring(index, match.start)));
      }
      final Color color;
      if (match.group(1) != null) {
        color = Pal.textDim;
      } else if (match.group(2) != null) {
        color = Pal.mint;
      } else if (match.group(3) != null) {
        color = Pal.sky;
      } else if (match.group(4) != null) {
        color = Pal.amber;
      } else {
        color = Pal.ember;
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(color: color),
      ));
      index = match.end;
    }
    if (index < line.length) {
      spans.add(TextSpan(text: line.substring(index)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final lines = code.split('\n');
    final name = path.split('/').last;

    return Scaffold(
      appBar: AppBar(
        leading: IconAction(
          icon: Icons.arrow_back_ios_new_rounded,
          tooltip: 'Back',
          size: 17,
          color: Pal.text,
          onTap: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Txt.title.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 2),
            Text(
              '$path · ${lines.length} lines',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Txt.meta.copyWith(fontSize: 10),
            ),
          ],
        ),
        actions: [
          IconAction(
            icon: Icons.copy_rounded,
            tooltip: 'Copy path',
            size: 18,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Path copied · $path')),
            ),
          ),
          const SizedBox(width: Sp.x2),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Hairline(),
        ),
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: Sp.x3, bottom: Sp.x8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x3, 0),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Pal.line),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 1; i <= lines.length; i++)
                      Text(
                        '$i',
                        style: Txt.code.copyWith(
                          fontSize: 11.5,
                          color: Pal.textDim.withOpacity(0.65),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.x3 + 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines)
                      Text.rich(
                        TextSpan(
                          style: Txt.code.copyWith(fontSize: 11.5),
                          children: _highlight(line),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
