import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'vfs.dart';

class SystemShellResult {
  const SystemShellResult({
    required this.output,
    required this.exitCode,
    required this.cwd,
  });

  final String output;
  final int exitCode;
  final String cwd;
}

/// Runs commands through the device's own shell (`/system/bin/sh` on Android)
/// so anything installed on the phone — git, curl, tar — works like it does in
/// Termux. Unlike the sandboxed [Shell] used by the agent, this is not limited
/// to file verbs.
class SystemShell {
  SystemShell(this.fs);

  final ProjectFs fs;
  String cwd = '';
  Process? _active;

  String get cwdDisplay => cwd.isEmpty ? fs.rootPath : fs.absolute(cwd);
  bool get running => _active != null;

  static String get shellPath =>
      Platform.isAndroid ? '/system/bin/sh' : '/bin/sh';

  void cancel() {
    _active?.kill(ProcessSignal.sigint);
    _active = null;
  }

  Future<SystemShellResult> run(
    String raw, {
    void Function(String chunk)? onStdout,
    void Function(String chunk)? onStderr,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final command = raw.trim();
    if (command.isEmpty) {
      return SystemShellResult(output: '', exitCode: 0, cwd: cwdDisplay);
    }
    final cd = _asCd(command);
    if (cd != null) return _changeDirectory(cd);

    final output = StringBuffer();
    Process process;
    try {
      process = await Process.start(
        shellPath,
        ['-c', command],
        workingDirectory: fs.absolute(cwd),
        environment: {
          'HOME': fs.rootPath,
          'PWD': fs.absolute(cwd),
        },
        includeParentEnvironment: true,
      );
    } on ProcessException catch (error) {
      final message = 'shell unavailable: ${error.message}';
      return SystemShellResult(
        output: message,
        exitCode: 127,
        cwd: cwdDisplay,
      );
    } on FileSystemException catch (error) {
      final message = 'shell unavailable: ${error.message}';
      return SystemShellResult(
        output: message,
        exitCode: 127,
        cwd: cwdDisplay,
      );
    }

    _active = process;
    final done = Completer<int>();
    final outDone = Completer<void>();
    final errDone = Completer<void>();
    const decoder = Utf8Decoder(allowMalformed: true);
    process.stdout.transform(decoder).listen((chunk) {
      output.write(chunk);
      onStdout?.call(chunk);
    }, onDone: () {
      if (!outDone.isCompleted) outDone.complete();
    });
    process.stderr.transform(decoder).listen((chunk) {
      output.write(chunk);
      onStderr?.call(chunk);
    }, onDone: () {
      if (!errDone.isCompleted) errDone.complete();
    });
    process.exitCode.then((code) {
      if (!done.isCompleted) done.complete(code);
    }).catchError((Object error) {
      if (!done.isCompleted) done.complete(1);
    });

    int exitCode;
    try {
      exitCode = await done.future.timeout(timeout);
      // The process is gone, but its piped output may still be in flight.
      await outDone.future
          .timeout(const Duration(seconds: 5), onTimeout: () {});
      await errDone.future
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      output.write('\n[timed out after ${timeout.inSeconds}s]');
      exitCode = 124;
    } finally {
      _active = null;
    }

    return SystemShellResult(
      output: output.toString(),
      exitCode: exitCode,
      cwd: cwdDisplay,
    );
  }

  String? _asCd(String command) {
    final match = RegExp(r'^cd(?:\s+(.*))?$').firstMatch(command);
    if (match == null) return null;
    var target = (match.group(1) ?? '').trim();
    if ((target.startsWith('"') && target.endsWith('"')) ||
        (target.startsWith("'") && target.endsWith("'"))) {
      target = target.substring(1, target.length - 1);
    }
    return target;
  }

  Future<SystemShellResult> _changeDirectory(String target) async {
    String next;
    try {
      if (target.isEmpty || target == '~') {
        next = '';
      } else if (target == '-') {
        next = cwd;
      } else if (target.startsWith('/')) {
        next = fs.normalize(target);
      } else {
        next = fs.normalize(cwd.isEmpty ? target : '$cwd/$target');
      }
    } on FsError {
      return SystemShellResult(
        output: 'cd: outside the project: $target',
        exitCode: 1,
        cwd: cwdDisplay,
      );
    }
    final dir = Directory(fs.absolute(next));
    if (!await dir.exists()) {
      return SystemShellResult(
        output: 'cd: no such directory: ${target.isEmpty ? '~' : target}',
        exitCode: 1,
        cwd: cwdDisplay,
      );
    }
    cwd = next;
    return SystemShellResult(output: '', exitCode: 0, cwd: cwdDisplay);
  }
}
