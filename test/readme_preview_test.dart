import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/widgets/github_markdown.dart';

void main() {
  test('local README images and picture variants become data URIs', () async {
    const source = '''
![Logo](./cards/logo.svg)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./cards/card-dark.svg">
    <img alt="Card" src="./cards/card-light.svg" width="600">
  </picture>
</p>

[![Build](https://img.shields.io/badge/build-passing-green)](https://example.test)
''';
    final requested = <String>[];
    final html = await readmePreviewBody(
      source,
      readmePath: 'README.md',
      dark: true,
      loadLocal: (uri) async {
        requested.add(uri.path);
        return Uint8List.fromList(utf8.encode('<svg></svg>'));
      },
    );

    expect(
      requested,
      containsAll(['cards/logo.svg', 'cards/card-dark.svg']),
    );
    expect(html, isNot(contains('<picture')));
    expect(html, isNot(contains('./cards/')));
    expect('data:image/svg+xml;base64,'.allMatches(html).length, 2);
    expect(html, contains('https://img.shields.io/badge/build-passing-green'));
  });
}
