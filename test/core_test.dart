import 'dart:io';

import 'package:devnest/core/shell.dart';
import 'package:devnest/core/vfs.dart';
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
