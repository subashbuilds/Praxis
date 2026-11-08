import 'dart:io';

import 'package:praxis/core/file_types.dart';
import 'package:praxis/core/readme_html.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/system_shell.dart';
import 'package:praxis/core/vfs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('devnest_test_');
    fs = ProjectFs(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('ProjectFs', () {
    test('writes, reads and lists nested files', () async {
      await fs.write('lib/main.dart', 'void main() {}');
      await fs.write('index.html', '<h1>hi</h1>');

      expect(await fs.read('lib/main.dart'), 'void main() {}');
      final entries = await fs.list();
      expect(entries.map((e) => e.path),
          containsAll(['lib', 'lib/main.dart', 'index.html']));
      expect(entries.first.isDir, isTrue, reason: 'directories sort first');
    });

    test('rejects path traversal outside the project', () async {
      expect(() => fs.normalize('../secrets.txt'), throwsA(isA<FsError>()));
      expect(() => fs.normalize('a/../../b'), throwsA(isA<FsError>()));
      expect(fs.normalize('a/./b'), 'a/b');
    });

    test('deletes a folder recursively', () async {
      await fs.write('src/a.dart', 'a');
      await fs.write('src/nested/b.dart', 'b');
      await fs.delete('src');
      expect(await fs.exists('src'), isFalse);
    });

    test('preserves binary bytes and never decodes them as text', () async {
      final bytes = <int>[0x89, 0x50, 0x4e, 0x47, 0x00, 0xff, 0x10, 0x42];
      await fs.writeBytes('assets/aiva.png', bytes);
      expect(await fs.readBytes('assets/aiva.png'), bytes);
      await expectLater(
        fs.read('assets/aiva.png'),
        throwsA(isA<FsError>()),
      );
      final snapshot = await fs.localSnapshot();
      expect(snapshot.hashes['assets/aiva.png'], gitBlobSha(bytes));
      expect(snapshot.texts.containsKey('assets/aiva.png'), isFalse);
      await fs.copy('assets/aiva.png', 'assets/copy.png');
      expect(await fs.readBytes('assets/copy.png'), bytes);
    });

    test('keeps hidden repository files while hiding app state', () async {
      await fs.write('.github/workflows/ci.yml', 'name: CI');
      await fs.write('.gitignore', 'build/');
      expect((await fs.list()).map((entry) => entry.path),
          isNot(contains('.gitignore')));
      final all = await fs.list(includeHidden: true);
      expect(all.map((entry) => entry.path),
          containsAll(['.gitignore', '.github/workflows/ci.yml']));
      await fs.write('.praxis/push.json', '{}');
      expect(
        (await fs.list(includeHidden: true)).map((entry) => entry.path),
        isNot(contains('.praxis/push.json')),
      );
    });
  });

  group('README HTML', () {
    test('turns common README HTML into visible Markdown', () {
      final markdown = markdownFromReadme(
        '<h2 align="center">Telegram MediaInfoBot</h2>\n'
        '<p><img src="https://example.test/badge.svg" alt="build"/> '
        '<b>fast</b></p>\n'
        '# Real heading',
      );
      expect(markdown, contains('## Telegram MediaInfoBot'));
      expect(markdown, contains('![build](https://example.test/badge.svg)'));
      expect(markdown, contains('**fast**'));
      expect(markdown, contains('# Real heading'));
    });

    test('joins a run of badges into one inline row', () {
      final markdown = markdownFromReadme(
        '[![Build](https://img.test/build.svg)](https://ci.test)\n'
        '[![Version](https://img.test/v.svg)](https://release.test)\n'
        '\n'
        '# Hello',
      );
      expect(
        markdown,
        contains(
          '[![Build](https://img.test/build.svg)](https://ci.test) '
          '[![Version](https://img.test/v.svg)](https://release.test)',
        ),
      );
      expect(markdown, contains('# Hello'));
    });
  });

  group('Shell', () {
    test('pwd starts at the root and cd moves into a folder', () async {
      await fs.createDir('lib');
      final shell = Shell(fs);

      var result = await shell.run('pwd');
      expect(result.lines.single.text, '/');

      result = await shell.run('cd lib');
      expect(shell.cwd, 'lib');
      result = await shell.run('pwd');
      expect(result.lines.single.text, '/lib');
    });

    test('the device shell creates .praxis and can enter it', () async {
      if (Platform.isAndroid) return;
      final shell = SystemShell(fs);
      expect(shell.promptDisplay, '~/');
      final result = await shell.run('cd .praxis');
      expect(result.exitCode, 0);
      expect(shell.promptDisplay, '.praxis/');
      expect(await fs.isDirectory('.praxis'), isTrue);
    });

    test('echo with redirection creates a real file', () async {
      final shell = Shell(fs);
      await shell.run('echo "hello shell" > note.txt');
      expect(await fs.read('note.txt'), 'hello shell\n');
      await shell.run('echo "second" >> note.txt');
      expect(await fs.read('note.txt'), 'hello shell\nsecond\n');
    });

    test('ls, cat, mkdir, rm and tree work on disk', () async {
      final shell = Shell(fs);
      await shell.run('mkdir docs');
      await shell.run('echo "read me" > docs/readme.md');

      var result = await shell.run('ls');
      expect(result.lines.first.text, 'docs/');

      result = await shell.run('cat docs/readme.md');
      expect(result.lines.first.text, 'read me');

      result = await shell.run('cat missing.txt');
      expect(result.lines.single.tone, ShellTone.error);

      await shell.run('rm -r docs');
      expect(await fs.exists('docs'), isFalse);
    });

    test('unsupported runtimes fail with a clear message', () async {
      final shell = Shell(fs);
      final result = await shell.run('node -v');
      expect(result.lines.first.text, contains('command not found'));
      expect(result.lines.last.text, contains('no runtimes'));
    });
  });
}
