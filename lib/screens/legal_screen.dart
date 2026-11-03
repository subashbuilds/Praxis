import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../theme/tokens.dart';
import '../widgets/common.dart';

enum LegalDoc { privacy, terms }

class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc doc;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  static const _langs = ['en', 'ru', 'uz'];

  String _lang = 'en';
  late Future<String> _text = _load();

  Future<String> _load() {
    final base =
        widget.doc == LegalDoc.privacy ? 'privacy_policy' : 'terms_of_use';
    return rootBundle.loadString('assets/legal/${base}_$_lang.md');
  }

  void _select(String lang) {
    if (lang == _lang) return;
    setState(() {
      _lang = lang;
      _text = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.doc == LegalDoc.privacy ? 'Privacy policy' : 'Terms of use';

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
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Txt.title.copyWith(fontSize: 17),
        ),
        actions: [
          for (final lang in _langs)
            GestureDetector(
              onTap: () => _select(lang),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: Motion.fast,
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _lang == lang ? Pal.ember.withOpacity(0.14) : null,
                  borderRadius: Rd.pill,
                ),
                child: Text(
                  lang.toUpperCase(),
                  style: Txt.meta.copyWith(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: _lang == lang ? Pal.ember : Pal.textDim,
                  ),
                ),
              ),
            ),
          const SizedBox(width: Sp.x2),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Hairline(),
        ),
      ),
      body: FutureBuilder<String>(
        future: _text,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(
              child: Text('Document unavailable', style: Txt.bodySoft),
            );
          }
          return _Markdown(source: snapshot.data!);
        },
      ),
    );
  }
}

class _Markdown extends StatelessWidget {
  const _Markdown({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    for (final raw in source.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        blocks.add(const SizedBox(height: 8));
      } else if (trimmed.startsWith('### ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: Sp.x3, bottom: 5),
          child: Text(
            trimmed.substring(4),
            style: Txt.label.copyWith(
              color: Pal.text,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ));
      } else if (trimmed.startsWith('## ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: Sp.x4 + 2, bottom: 6),
          child: Text(trimmed.substring(3),
              style: Txt.title.copyWith(fontSize: 14.5)),
        ));
      } else if (trimmed.startsWith('# ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: Sp.x3),
          child: Text(trimmed.substring(2),
              style: Txt.headline.copyWith(fontSize: 23)),
        ));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 8),
                child: Text('·', style: Txt.body.copyWith(color: Pal.ember)),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: Txt.bodySoft,
                    children: _inline(trimmed.substring(2)),
                  ),
                ),
              ),
            ],
          ),
        ));
      } else {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Text.rich(
            TextSpan(style: Txt.bodySoft, children: _inline(trimmed)),
          ),
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, Sp.x10),
      children: blocks,
    );
  }

  List<TextSpan> _inline(String text) {
    final spans = <TextSpan>[];
    final bold = RegExp(r'\*\*(.+?)\*\*');
    var index = 0;
    for (final match in bold.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.text),
      ));
      index = match.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return spans;
  }
}
