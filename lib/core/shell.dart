import 'vfs.dart';

enum ShellTone { command, output, muted, error, accent }

class ShellLine {
  const ShellLine(this.text, [this.tone = ShellTone.output]);
  final String text;
  final ShellTone tone;
}

class ShellResult {
  const ShellResult(this.lines, {required this.cwd, this.clear = false});
  final List<ShellLine> lines;
  final String cwd;
  final bool clear;
}

/// A real shell over the project directory: it lists, reads, writes, moves and
/// deletes actual files. It is not a POSIX environment — there is no Node,
/// Python or git binary — so those commands fail with a clear message instead
/// of pretending.
class Shell {
  Shell(this.fs);
  final ProjectFs fs;
  String cwd = '';

  String get cwdDisplay => '/$cwd';

  Future<ShellResult> run(String raw) async {
    final input = raw.trim();
    if (input.isEmpty) return ShellResult(const [], cwd: cwd);
    final tokens = _tokenize(input);
    if (tokens.isEmpty) return ShellResult(const [], cwd: cwd);
    final command = tokens.first;
    final args = tokens.sublist(1);

    try {
      switch (command) {
        case 'clear':
          return ShellResult(const [], cwd: cwd, clear: true);
        case 'pwd':
          return _out(cwdDisplay);
        case 'cd':
          return await _cd(args);
        case 'ls':
          return await _ls(args);
        case 'cat':
          return await _cat(args);
        case 'echo':
          return await _echo(args);
        case 'mkdir':
          return await _mkdir(args);
        case 'touch':
          return await _touch(args);
        case 'rm':
          return await _rm(args);
        case 'mv':
          return await _mv(args);
        case 'cp':
          return await _cp(args);
        case 'tree':
          return await _tree(args);
        case 'find':
          return await _find(args);
        case 'grep':
          return await _grep(args);
        case 'wc':
          return await _wc(args);
        case 'head':
          return await _head(args, fromEnd: false);
        case 'tail':
          return await _head(args, fromEnd: true);
        case 'help':
          return _help();
        case 'whoami':
          return _out('praxis');
        case 'date':
          return _out(DateTime.now().toIso8601String());
        default:
          return _missing(command);
      }
    } on FsError catch (error) {
      return _err(error.message);
    } catch (error) {
      return _err('praxis: $error');
    }
  }

  String _resolve(String path) {
    if (path.isEmpty) return cwd;
    if (path == '~' || path == '/') return '';
    if (path.startsWith('~')) return fs.normalize(path.substring(1));
    if (path.startsWith('/')) return fs.normalize(path);
    return fs.normalize(cwd.isEmpty ? path : '$cwd/$path');
  }

  String _display(String rel) => rel.isEmpty ? '/' : '/$rel';

  ShellResult _out(String text, [ShellTone tone = ShellTone.output]) =>
      ShellResult([ShellLine(text, tone)], cwd: cwd);

  ShellResult _err(String text) =>
      ShellResult([ShellLine(text, ShellTone.error)], cwd: cwd);

  Future<ShellResult> _cd(List<String> args) async {
    final target = _resolve(args.isEmpty ? '' : args.first);
    if (!await fs.isDirectory(target)) {
      return _err('cd: no such directory: ${args.isEmpty ? '~' : args.first}');
    }
    cwd = target;
    return ShellResult(const [], cwd: cwd);
  }

  Future<ShellResult> _ls(List<String> args) async {
    final pathArg = args.where((a) => !a.startsWith('-')).toList();
    final target = _resolve(pathArg.isEmpty ? cwd : pathArg.first);
    final entries = await fs.list(path: target, recursive: false);
    if (entries.isEmpty) {
      return ShellResult([const ShellLine('(empty)', ShellTone.muted)],
          cwd: cwd);
    }
    final names = entries.map((e) => e.isDir ? '${e.name}/' : e.name).toList();
    return ShellResult(
      names.map((n) => ShellLine(n)).toList(),
      cwd: cwd,
    );
  }

  Future<ShellResult> _cat(List<String> args) async {
    if (args.isEmpty) return _err('cat: missing file operand');
    final lines = <ShellLine>[];
    for (final arg in args) {
      final content = await fs.read(_resolve(arg));
      lines.addAll(content.split('\n').map(ShellLine.new));
    }
    return ShellResult(lines, cwd: cwd);
  }

  Future<ShellResult> _echo(List<String> args) async {
    final marker = args.indexWhere((a) => a == '>' || a == '>>');
    if (marker < 0) {
      return _out(args.join(' '));
    }
    if (marker + 1 >= args.length) {
      return _err('echo: missing file after ${args[marker]}');
    }
    final append = args[marker] == '>>';
    final target = _resolve(args[marker + 1]);
    final text = args.sublist(0, marker).join(' ');
    final existing =
        append && await fs.exists(target) ? await fs.read(target) : '';
    await fs.write(target, '$existing$text\n');
    return ShellResult(const [], cwd: cwd);
  }

  Future<ShellResult> _mkdir(List<String> args) async {
    final paths = args.where((a) => !a.startsWith('-')).toList();
    if (paths.isEmpty) return _err('mkdir: missing operand');
    for (final path in paths) {
      await fs.createDir(_resolve(path));
    }
    return ShellResult(const [], cwd: cwd);
  }

  Future<ShellResult> _touch(List<String> args) async {
    if (args.isEmpty) return _err('touch: missing file operand');
    for (final arg in args) {
      final target = _resolve(arg);
      if (!await fs.exists(target)) await fs.write(target, '');
    }
    return ShellResult(const [], cwd: cwd);
  }

  Future<ShellResult> _rm(List<String> args) async {
    final paths = args.where((a) => !a.startsWith('-')).toList();
    if (paths.isEmpty) return _err('rm: missing operand');
    for (final path in paths) {
      await fs.delete(_resolve(path));
    }
    return ShellResult(const [], cwd: cwd);
  }

  Future<ShellResult> _mv(List<String> args) async {
    if (args.length < 2) return _err('mv: usage: mv <source> <target>');
    await fs.rename(_resolve(args[0]), _resolve(args[1]));
    return ShellResult(const [], cwd: cwd);
  }

  Future<ShellResult> _cp(List<String> args) async {
    if (args.length < 2) return _err('cp: usage: cp <source> <target>');
    await fs.copy(_resolve(args[0]), _resolve(args[1]));
    return ShellResult(const [], cwd: cwd);
  }

  Future<ShellResult> _tree(List<String> args) async {
    final target = _resolve(args.isEmpty ? cwd : args.first);
    final entries = await fs.list(path: target);
    if (entries.isEmpty) return _out('(empty)', ShellTone.muted);
    final lines = <ShellLine>[ShellLine(_display(target), ShellTone.muted)];
    final baseDepth = target.isEmpty ? 0 : target.split('/').length;
    for (final entry in entries) {
      final depth = (entry.path.split('/').length - baseDepth).clamp(1, 12);
      final pad = '  ' * depth;
      lines
          .add(ShellLine('$pad${entry.isDir ? '${entry.name}/' : entry.name}'));
    }
    return ShellResult(lines, cwd: cwd);
  }

  Future<ShellResult> _find(List<String> args) async {
    final pattern =
        args.isEmpty ? '' : args.last.replaceAll('"', '').replaceAll("'", '');
    final entries = await fs.list(path: cwd);
    final hits = entries
        .where((e) => pattern.isEmpty || e.path.contains(pattern))
        .map((e) => ShellLine(_display(e.path)))
        .toList();
    if (hits.isEmpty) return _out('no matches', ShellTone.muted);
    return ShellResult(hits, cwd: cwd);
  }

  Future<ShellResult> _grep(List<String> args) async {
    if (args.length < 2) return _err('grep: usage: grep <pattern> <file>');
    final pattern = args[0];
    final content = await fs.read(_resolve(args[1]));
    final lines = <ShellLine>[];
    final source = content.split('\n');
    for (var i = 0; i < source.length; i++) {
      if (source[i].contains(pattern)) {
        lines.add(ShellLine('${i + 1}: ${source[i]}'));
      }
    }
    if (lines.isEmpty) return _out('no matches', ShellTone.muted);
    return ShellResult(lines, cwd: cwd);
  }

  Future<ShellResult> _wc(List<String> args) async {
    final paths = args.where((a) => !a.startsWith('-')).toList();
    if (paths.isEmpty) return _err('wc: missing file operand');
    final lines = <ShellLine>[];
    for (final path in paths) {
      final content = await fs.read(_resolve(path));
      final count = content.isEmpty ? 0 : content.split('\n').length;
      final bytes = content.length;
      lines.add(ShellLine('$count\t$bytes\t$path'));
    }
    return ShellResult(lines, cwd: cwd);
  }

  Future<ShellResult> _head(List<String> args, {required bool fromEnd}) async {
    var count = 10;
    final paths = <String>[];
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '-n' && i + 1 < args.length) {
        count = int.tryParse(args[i + 1]) ?? count;
        i++;
      } else if (!args[i].startsWith('-')) {
        paths.add(args[i]);
      }
    }
    if (paths.isEmpty) {
      return _err('usage: ${fromEnd ? 'tail' : 'head'} -n <lines> <file>');
    }
    final content = await fs.read(_resolve(paths.first));
    final all = content.split('\n');
    final slice = fromEnd
        ? all.sublist(all.length - count.clamp(0, all.length))
        : all.take(count).toList();
    return ShellResult(slice.map(ShellLine.new).toList(), cwd: cwd);
  }

  ShellResult _help() => ShellResult(
        const [
          ShellLine(
              'files      ls · cd · pwd · cat · tree · find · grep · wc · head · tail'),
          ShellLine(
              'write      echo "text" > file · touch · mkdir · rm · mv · cp'),
          ShellLine('session    clear · whoami · date · help'),
          ShellLine('', ShellTone.muted),
          ShellLine(
              'Runs on the project folder on this device. Node, Python and git',
              ShellTone.muted),
          ShellLine('are not bundled — the agent writes files instead.',
              ShellTone.muted),
        ],
        cwd: cwd,
      );

  ShellResult _missing(String command) => ShellResult(
        [
          ShellLine('praxis: command not found: $command', ShellTone.error),
          if (const {
            'node',
            'npm',
            'python',
            'python3',
            'flutter',
            'git',
            'npx',
            'dart'
          }.contains(command))
            const ShellLine(
              'This shell has no runtimes; it only edits project files.',
              ShellTone.muted,
            ),
        ],
        cwd: cwd,
      );

  List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          buffer.write(char);
        }
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == ' ' || char == '\t') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());
    return tokens;
  }
}
