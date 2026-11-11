import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/project_search.dart';
import 'package:praxis/core/vfs.dart';

void main() {
  test('search reaches files inside folders in a cloned project', () async {
    final dir = await Directory.systemTemp.createTemp('praxis-search-');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/src').create();
    await File('${dir.path}/README.md').writeAsString('intro\n');
    await File('${dir.path}/src/index.html')
        .writeAsString('<p>praxis marker</p>\n');

    final result = await ProjectSearch.run(ProjectFs(dir), 'praxis');

    expect(result.files.map((file) => file.path), contains('src/index.html'));
    expect(result.codeMatches, 1);
    expect(result.files.first.matches.first.line, 1);
  });

  test('search ignores folder names instead of stopping at them', () async {
    final dir = await Directory.systemTemp.createTemp('praxis-search-');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/target').create();
    await File('${dir.path}/target/notes.txt').writeAsString('target here\n');

    final result = await ProjectSearch.run(ProjectFs(dir), 'target');

    expect(result.files.map((file) => file.name), contains('notes.txt'));
    expect(result.fileMatches, 0);
    expect(result.codeMatches, 1);
  });
}
