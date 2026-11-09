import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_paths.dart';

/// A runtime that can be installed into the Alpine rootfs with apk.
enum LinuxRuntime { node, python, php, go }

extension LinuxRuntimeInfo on LinuxRuntime {
  String get label => switch (this) {
        LinuxRuntime.node => 'Node.js',
        LinuxRuntime.python => 'Python',
        LinuxRuntime.php => 'PHP',
        LinuxRuntime.go => 'Go',
      };

  String get shortLabel => switch (this) {
        LinuxRuntime.node => 'NODE',
        LinuxRuntime.python => 'PY',
        LinuxRuntime.php => 'PHP',
        LinuxRuntime.go => 'GO',
      };

  String get versionCommand => switch (this) {
        LinuxRuntime.node => 'node --version',
        LinuxRuntime.python => 'python3 --version',
        LinuxRuntime.php => 'php --version',
        LinuxRuntime.go => 'go version',
      };

  String get checkCommand => switch (this) {
        LinuxRuntime.node => 'node',
        LinuxRuntime.python => 'python3',
        LinuxRuntime.php => 'php',
        LinuxRuntime.go => 'go',
      };

  /// Alpine 3.21 ships PHP 8.3. The package set mirrors the extensions the
  /// workbench needs for Laravel and plain PHP projects.
  List<String> get packages => switch (this) {
        LinuxRuntime.node => const ['nodejs', 'npm'],
        LinuxRuntime.python => const [
            'python3',
            'py3-pip',
            'py3-virtualenv',
            'tzdata',
          ],
        LinuxRuntime.php => const [
            'php83',
            'php83-mbstring',
            'php83-openssl',
            'php83-pdo',
            'php83-tokenizer',
            'php83-xml',
            'php83-curl',
            'php83-zip',
            'php83-phar',
            'php83-dom',
            'php83-iconv',
            'php83-fileinfo',
            'php83-session',
            'php83-ctype',
            'php83-xmlwriter',
            'sqlite',
            'php83-sqlite3',
            'php83-pdo_sqlite',
            'lighttpd',
            'php83-cgi',
          ],
        LinuxRuntime.go => const ['go'],
      };

  List<String> get templates => switch (this) {
        LinuxRuntime.node => const [
            'React',
            'React + Tailwind',
            'Vue',
            'Svelte',
            'Next.js',
            'Nuxt',
            'Express.js',
            'NestJS',
            'Discord.js',
            'React Native (Expo)',
          ],
        LinuxRuntime.python => const [
            'Django',
            'FastAPI',
            'Flask (Python)',
            'aiogram (Python)',
          ],
        LinuxRuntime.php => const ['Laravel', 'PHP'],
        LinuxRuntime.go => const ['Go (Golang)'],
      };
}

class LinuxRuntimeStatus {
  const LinuxRuntimeStatus({
    required this.runtime,
    this.installed = false,
    this.busy = false,
    this.version = '',
    this.error = '',
  });

  final LinuxRuntime runtime;
  final bool installed;
  final bool busy;
  final String version;
  final String error;

  LinuxRuntimeStatus copyWith({
    bool? installed,
    bool? busy,
    String? version,
    String? error,
  }) =>
      LinuxRuntimeStatus(
        runtime: runtime,
        installed: installed ?? this.installed,
        busy: busy ?? this.busy,
        version: version ?? this.version,
        error: error ?? this.error,
      );
}

class LinuxProcess {
  const LinuxProcess({
    required this.pid,
    required this.name,
    required this.user,
    this.cpu = '',
    this.memory = '',
    this.rssKb = 0,
  });

  final String pid;
  final String name;
  final String user;
  final String cpu;
  final String memory;
  final int rssKb;
}

class LinuxSnapshot {
  const LinuxSnapshot({
    this.diskBytes = 0,
    this.cacheBytes = 0,
    this.projectBytes = 0,
    this.ramUsedBytes,
    this.ramTotalBytes,
    this.load1,
    this.cpuPercent,
    this.processes = const [],
    this.measuredAt,
  });

  final int diskBytes;
  final int cacheBytes;
  final int projectBytes;

  /// Memory currently used by guest processes, not the phone's total RAM.
  final int? ramUsedBytes;
  final int? ramTotalBytes;
  final double? load1;

  /// Sum of CPU percentages of guest processes only.
  final double? cpuPercent;
  final List<LinuxProcess> processes;
  final DateTime? measuredAt;
}

class LinuxResult {
  const LinuxResult({
    required this.output,
    required this.exitCode,
    required this.cancelled,
  });

  final String output;
  final int exitCode;
  final bool cancelled;
}

class LinuxUnavailableException implements Exception {
  const LinuxUnavailableException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Manages the bundled Alpine minirootfs and the proot process that runs it.
///
/// The rootfs and the copied proot binary live beside the app, not inside a
/// project. A project is bind-mounted at /workspace for each command, so
/// resetting the environment never deletes the user's code.
class LinuxEnvironment extends ChangeNotifier {
  LinuxEnvironment({
    required this.base,
    Future<String?> Function()? nativeLibraryDir,
    AssetBundle? assets,
  })  : _nativeLibraryDir = nativeLibraryDir ?? NativePaths.nativeLibraryDir,
        _assets = assets ?? rootBundle;

  static const rootfsAsset =
      'assets/alpine/alpine-minirootfs-3.21.7-aarch64.tar.gz';
  static const version = '3.21.7';

  final Directory base;
  final Future<String?> Function() _nativeLibraryDir;
  final AssetBundle _assets;

  LinuxState state = LinuxState.idle;
  String error = '';
  String phase = '';
  String rootfsPath = '';
  String prootPath = '';
  String prootLoaderPath = '';
  bool packageCaching = true;
  LinuxSnapshot snapshot = const LinuxSnapshot();
  final Map<LinuxRuntime, LinuxRuntimeStatus> runtimes = {
    for (final runtime in LinuxRuntime.values)
      runtime: LinuxRuntimeStatus(runtime: runtime),
  };

  Process? _active;
  bool _cancelled = false;
  Future<void>? _preparing;
  Timer? _refreshTimer;
  bool _refreshing = false;

  File get _runtimesFile => File('${base.path}/runtimes.json');

  bool get ready => state == LinuxState.ready;
  bool get busy => state == LinuxState.preparing;

  Future<void> prepare({bool force = false}) {
    if (_preparing != null) return _preparing!;
    if (ready && !force) return Future.value();
    final job = _prepare(force: force);
    _preparing = job;
    return job.whenComplete(() {
      _preparing = null;
    });
  }

  Future<void> _prepare({required bool force}) async {
    state = LinuxState.preparing;
    error = '';
    phase = 'Preparing Alpine ${LinuxEnvironment.version}';
    notifyListeners();
    try {
      await base.create(recursive: true);
      rootfsPath = '${base.path}/rootfs';
      if (force && await Directory(rootfsPath).exists()) {
        await Directory(rootfsPath).delete(recursive: true);
      }
      // Older builds could leave a `.praxis-ready` marker behind after failing
      // to reproduce Alpine's symlinks. Treat a rootfs without a real shell as
      // invalid and rebuild it instead of launching a permanently broken env.
      if (!await File('$rootfsPath/.praxis-ready').exists() ||
          !await _rootfsIsBootable()) {
        if (await Directory(rootfsPath).exists()) {
          await Directory(rootfsPath).delete(recursive: true);
        }
        phase = 'Extracting Alpine minirootfs';
        notifyListeners();
        final data = await _assets.load(rootfsAsset);
        await _extractRootfs(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        await _finishRootfs();
      }
      if (Platform.isAndroid) {
        phase = 'Finding proot';
        notifyListeners();
        final libraryDir = await _nativeLibraryDir();
        if (libraryDir == null || libraryDir.isEmpty) {
          throw const LinuxUnavailableException(
            'Android did not provide its native library directory.',
          );
        }
        final bundled = File('$libraryDir/libproot.so');
        if (!await bundled.exists()) {
          throw const LinuxUnavailableException(
            'libproot.so is missing from the APK native libraries.',
          );
        }
        // PRoot hands every guest exec to its companion loader. Without
        // PROOT_LOADER it looks for a path that is not in the APK and reports
        // a misleading ENOENT for /bin/busybox.
        final bundledLoader = File('$libraryDir/libproot-loader.so');
        if (!await bundledLoader.exists()) {
          throw const LinuxUnavailableException(
            'libproot-loader.so is missing from the APK native libraries.',
          );
        }
        // nativeLibraryDir is the executable location supplied by Android.
        // Copying proot into app data can hit Android 10+ W^X restrictions.
        prootPath = bundled.path;
        prootLoaderPath = bundledLoader.path;
      } else {
        prootPath = '';
      }
      await _loadRuntimeState();
      state = LinuxState.ready;
      phase = 'Ready';
      notifyListeners();
      await refresh();
      _startRefreshTimer();
    } catch (exception) {
      state = LinuxState.error;
      error = '$exception';
      phase = '';
      notifyListeners();
    }
  }

  Future<void> _extractRootfs(Uint8List bytes) async {
    final decoded = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(decoded);
    final root = Directory(rootfsPath);
    await root.create(recursive: true);
    var files = 0;
    final links = <({String path, String target})>[];
    for (final entry in archive) {
      var name = entry.name.replaceAll('\\', '/');
      while (name.startsWith('./')) {
        name = name.substring(2);
      }
      if (name.isEmpty || name == '.') continue;
      final parts = name.split('/').where((part) => part.isNotEmpty).toList();
      if (parts.isEmpty ||
          parts.contains('..') ||
          name.startsWith('/') ||
          name.contains('\u0000')) {
        continue;
      }
      final relative = parts.join(Platform.pathSeparator);
      final target = '${root.path}${Platform.pathSeparator}$relative';
      if (entry.isSymbolicLink) {
        // Tar stores a symlink target in the header, not in the entry body.
        // Reading entry.content here produced an empty target and could make
        // a directory link resolve to its own parent.
        final linkTarget = entry.nameOfLinkedFile.trim();
        if (linkTarget.isNotEmpty) {
          links.add((path: target, target: linkTarget));
        }
        continue;
      }
      if (entry.name.endsWith('/')) {
        await Directory(target).create(recursive: true);
        continue;
      }
      await File(target).parent.create(recursive: true);
      await File(target).writeAsBytes(entry.content as List<int>, flush: false);
      files++;
    }
    if (files == 0) {
      throw const LinuxUnavailableException(
        'The bundled Alpine archive did not contain any files.',
      );
    }
    // Android app-private storage usually permits symlinks, but some devices
    // and storage backends reject absolute targets. Materialising the link as
    // a hardlink (or a copy) is equivalent for files and avoids a rootfs that
    // says it is ready while /bin/sh is missing.
    for (final link in links) {
      await _materializeRootfsLink(link.path, link.target);
    }
    await _chmodRootfs();
  }

  Future<bool> _rootfsIsBootable() async {
    try {
      final shell = File('$rootfsPath/bin/sh');
      final busybox = File('$rootfsPath/bin/busybox');
      return await shell.exists() && await busybox.exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> _materializeRootfsLink(String path, String target) async {
    final resolved = _resolveRootfsTarget(path, target);
    if (resolved == null) return;
    await Directory(File(path).parent.path).create(recursive: true);
    if (resolved == File(path).absolute.path) return;
    if (await Directory(path).exists() ||
        await Link(path).exists() ||
        await File(path).exists()) {
      return;
    }
    final type = await FileSystemEntity.type(resolved, followLinks: true);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.directory) {
      await _copyRootfsDirectory(Directory(resolved), Directory(path));
      return;
    }
    // Prefer a hardlink: it preserves Alpine's `busybox` applet layout without
    // multiplying the rootfs size. Fall back to a byte copy on filesystems
    // that do not allow hardlinks.
    if (Platform.isAndroid) {
      final result = await Process.run('/system/bin/ln', [resolved, path]);
      if (result.exitCode == 0) return;
    }
    try {
      await File(resolved).copy(path);
    } catch (_) {
      // A missing vendor-specific link should not abort the rest of the rootfs.
    }
  }

  String? _resolveRootfsTarget(String linkPath, String target) {
    final root = rootfsPath.replaceAll(RegExp(r'/+$'), '');
    final raw = target.startsWith('/')
        ? '$root$target'
        : '${File(linkPath).parent.path}/$target';
    final parts = <String>[];
    for (final part in raw.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    final resolved = '/${parts.join('/')}';
    return resolved.startsWith('$root/') ? resolved : null;
  }

  Future<void> _copyRootfsDirectory(
      Directory source, Directory destination) async {
    final root = Directory(rootfsPath).absolute.path;
    final sourcePath = source.absolute.path;
    final destinationPath = destination.absolute.path;
    if (!sourcePath.startsWith('$root/') ||
        !destinationPath.startsWith('$root/')) {
      return;
    }
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final target = '${destination.path}${Platform.pathSeparator}$name';
      if (entity is Directory) {
        if (entity.absolute.path == destinationPath) continue;
        await _copyRootfsDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }

  Future<void> _finishRootfs() async {
    final root = Directory(rootfsPath);
    for (final name in const [
      'dev',
      'proc',
      'sys',
      'tmp',
      'root',
      'workspace'
    ]) {
      await Directory('${root.path}/$name').create(recursive: true);
    }
    await File('${root.path}/etc/resolv.conf').writeAsString(
      'nameserver 1.1.1.1\nnameserver 8.8.8.8\n',
    );
    await File('${root.path}/.praxis-ready').writeAsString(
      'Praxis Alpine ${LinuxEnvironment.version}\n',
    );
  }

  /// tar does not carry executable bits through Dart's file writes. A single
  /// recursive chmod is much cheaper than one process per binary and is enough
  /// for busybox, apk and installed runtimes.
  Future<void> _chmodRootfs() async {
    if (!Platform.isAndroid) return;
    final chmod = await File('/system/bin/chmod').exists()
        ? '/system/bin/chmod'
        : 'chmod';
    for (final folder in const [
      'bin',
      'sbin',
      'usr/bin',
      'usr/sbin',
      'lib',
      'usr/lib'
    ]) {
      final path = '$rootfsPath/$folder';
      if (!await Directory(path).exists()) continue;
      try {
        await Process.run(chmod, ['-R', '755', path]);
      } catch (_) {
        // A later command run will report the concrete permission error.
      }
    }
  }

  Future<LinuxResult> run(
    String command, {
    required String projectRoot,
    String cwd = '',
    Duration timeout = const Duration(seconds: 180),
    void Function(String chunk)? onStdout,
    void Function(String chunk)? onStderr,
  }) async {
    if (!ready) {
      await prepare();
    }
    if (!ready) {
      return LinuxResult(
        output: error.isEmpty ? 'Alpine is not ready.' : error,
        exitCode: 127,
        cancelled: false,
      );
    }
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return const LinuxResult(output: '', exitCode: 0, cancelled: false);
    }
    final guestCwd = _guestCwd(cwd);
    final hostTmp = Directory('${base.path}/tmp');
    await hostTmp.create(recursive: true);
    final args = <String>[
      if (Platform.isAndroid) ...['-0', '--link2symlink'],
      '-r',
      rootfsPath,
      '-b',
      '$projectRoot:/workspace',
      if (Directory('/dev').existsSync()) ...['-b', '/dev:/dev'],
      if (Directory('/proc').existsSync()) ...['-b', '/proc:/proc'],
      '-w',
      guestCwd,
      '/bin/busybox',
      'sh',
      '-c',
      trimmed,
    ];
    _cancelled = false;
    final output = StringBuffer();
    Process process;
    try {
      process = await Process.start(
        prootPath.isEmpty ? 'proot' : prootPath,
        args,
        workingDirectory: projectRoot,
        environment: {
          'HOME': '/root',
          'PATH':
              '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
          'TERM': 'xterm-256color',
          'LANG': 'C.UTF-8',
          'TMPDIR': '/tmp',
          'PROOT_TMP_DIR': hostTmp.path,
          if (prootLoaderPath.isNotEmpty) 'PROOT_LOADER': prootLoaderPath,
        },
        includeParentEnvironment: true,
      );
    } on ProcessException catch (exception) {
      return LinuxResult(
        output: 'proot unavailable: ${exception.message}',
        exitCode: 127,
        cancelled: false,
      );
    } on FileSystemException catch (exception) {
      return LinuxResult(
        output: 'proot unavailable: ${exception.message}',
        exitCode: 127,
        cancelled: false,
      );
    }
    _active = process;
    const decoder = Utf8Decoder(allowMalformed: true);
    final outDone = Completer<void>();
    final errDone = Completer<void>();
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
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
      await outDone.future
          .timeout(const Duration(seconds: 3), onTimeout: () {});
      await errDone.future
          .timeout(const Duration(seconds: 3), onTimeout: () {});
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      output.write('\n[timed out after ${timeout.inSeconds}s]');
      exitCode = 124;
    } finally {
      _active = null;
    }
    return LinuxResult(
      output: output.toString(),
      exitCode: _cancelled ? 130 : exitCode,
      cancelled: _cancelled,
    );
  }

  String _guestCwd(String cwd) {
    final clean = cwd
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
    return clean.isEmpty ? '/workspace' : '/workspace/$clean';
  }

  void cancel() {
    _cancelled = true;
    _active?.kill(ProcessSignal.sigint);
  }

  Future<void> install(LinuxRuntime runtime) async {
    if (!ready || runtimes[runtime]!.busy) return;
    final spec = runtimes[runtime]!;
    runtimes[runtime] = spec.copyWith(busy: true, error: '');
    notifyListeners();
    final result = await run(
      'apk add --no-cache ${runtime.packages.join(' ')}',
      projectRoot: _lastProjectRoot ?? base.path,
      timeout: const Duration(minutes: 10),
    );
    final installed = result.exitCode == 0;
    var version = '';
    if (installed) {
      final check = await run(
        '${runtime.versionCommand} 2>&1 | head -n 1',
        projectRoot: _lastProjectRoot ?? base.path,
      );
      version = check.output.trim();
    }
    runtimes[runtime] = runtimes[runtime]!.copyWith(
      busy: false,
      installed: installed,
      version: version,
      error: installed ? '' : _lastLine(result.output),
    );
    await _saveRuntimeState();
    notifyListeners();
    await refresh();
  }

  Future<void> _loadRuntimeState() async {
    try {
      if (!await _runtimesFile.exists()) return;
      final raw = jsonDecode(await _runtimesFile.readAsString());
      if (raw is! Map) return;
      for (final runtime in LinuxRuntime.values) {
        final item = raw[runtime.name];
        if (item is! Map) continue;
        final installed = item['installed'] as bool? ?? false;
        if (!installed) continue;
        runtimes[runtime] = runtimes[runtime]!.copyWith(
          installed: true,
          version: item['version'] as String? ?? 'Installed',
        );
      }
      notifyListeners();
    } catch (_) {
      // A corrupt status file must not prevent Alpine from starting.
    }
  }

  Future<void> _saveRuntimeState() async {
    try {
      await base.create(recursive: true);
      await _runtimesFile.writeAsString(
          jsonEncode({
            for (final runtime in LinuxRuntime.values)
              runtime.name: {
                'installed': runtimes[runtime]!.installed,
                'version': runtimes[runtime]!.version,
              },
          }),
          flush: true);
    } catch (_) {}
  }

  String? _lastProjectRoot;

  Future<void> refresh({String? projectRoot}) async {
    if (projectRoot != null && projectRoot.isNotEmpty) {
      _lastProjectRoot = projectRoot;
    }
    if (!ready || _refreshing) return;
    _refreshing = true;
    try {
      final project = _lastProjectRoot ?? base.path;
      final ps = await run(
        'ps -o pid,user,pcpu,rss,comm 2>/dev/null || ps aux 2>/dev/null || ps',
        projectRoot: project,
        timeout: const Duration(seconds: 12),
      );
      final processes = _parseProcesses(ps.output);
      final ramBytes = processes.isEmpty
          ? null
          : processes.fold<int>(0, (sum, item) => sum + item.rssKb) * 1024;
      final cpu = processes.isEmpty
          ? null
          : processes.fold<double>(
              0,
              (sum, item) => sum + (double.tryParse(item.cpu) ?? 0),
            );
      snapshot = LinuxSnapshot(
        diskBytes: await _directorySize(Directory(rootfsPath)),
        cacheBytes: await _cacheSize(),
        projectBytes: await _directorySize(Directory(project)),
        ramUsedBytes: ramBytes,
        cpuPercent: cpu,
        processes: processes,
        measuredAt: DateTime.now(),
      );
      notifyListeners();
    } catch (_) {
      // Resource sampling is diagnostic; a failed ps must not hide the shell.
    } finally {
      _refreshing = false;
    }
  }

  List<LinuxProcess> _parseProcesses(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final result = <LinuxProcess>[];
    var pidIndex = 0;
    var userIndex = 1;
    var cpuIndex = 2;
    var rssIndex = 3;
    var nameIndex = 4;
    var sawHeader = false;
    for (final line in lines) {
      final columns = line.split(RegExp(r'\s+'));
      final lower = columns.map((value) => value.toLowerCase()).toList();
      if (!sawHeader && lower.contains('pid')) {
        sawHeader = true;
        pidIndex = lower.indexOf('pid');
        userIndex = lower.indexOf('user');
        cpuIndex = lower.indexOf('%cpu');
        rssIndex = lower.indexOf('rss');
        nameIndex = lower.indexOf('comm');
        if (userIndex < 0) userIndex = lower.indexOf('user');
        if (cpuIndex < 0) cpuIndex = lower.indexOf('pcpu');
        if (rssIndex < 0) rssIndex = lower.indexOf('rss');
        if (nameIndex < 0) nameIndex = lower.indexOf('command');
        continue;
      }
      if (columns.length <= pidIndex ||
          int.tryParse(columns[pidIndex]) == null) {
        continue;
      }
      String at(int index) =>
          index >= 0 && index < columns.length ? columns[index] : '';
      final pid = at(pidIndex);
      final user = at(userIndex);
      final cpu = at(cpuIndex);
      final rss = int.tryParse(at(rssIndex)) ?? 0;
      final start = nameIndex >= 0 ? nameIndex : columns.length - 1;
      final rawName = columns.sublist(start.clamp(0, columns.length)).join(' ');
      final name = rawName.split('/').last.trim();
      if (name.isEmpty) continue;
      result.add(LinuxProcess(
        pid: pid,
        user: user.isEmpty ? 'root' : user,
        cpu: cpu.isEmpty ? '0.0%' : '$cpu%',
        memory: humanBytes(rss * 1024),
        rssKb: rss,
        name: name.length > 28 ? name.substring(0, 28) : name,
      ));
    }
    return result;
  }

  Future<int> _cacheSize() async {
    var bytes = 0;
    for (final path in const [
      '/var/cache/apk',
      '/root/.cache',
      '/root/.npm',
      '/tmp',
    ]) {
      final directory = Directory('$rootfsPath$path');
      if (await directory.exists()) bytes += await _directorySize(directory);
    }
    return bytes;
  }

  Future<int> _directorySize(Directory directory) async {
    var bytes = 0;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            bytes += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return bytes;
  }

  Future<void> clearCache() async {
    if (!ready) return;
    await run(
      'rm -rf /var/cache/apk/* /root/.cache/* /root/.npm/* /tmp/*',
      projectRoot: _lastProjectRoot ?? base.path,
    );
    await refresh();
  }

  Future<void> reset() async {
    cancel();
    state = LinuxState.preparing;
    phase = 'Resetting Alpine';
    notifyListeners();
    await base.delete(recursive: true);
    state = LinuxState.idle;
    notifyListeners();
    await prepare(force: true);
  }

  void setPackageCaching(bool enabled) {
    packageCaching = enabled;
    notifyListeners();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(refresh());
    });
  }

  String _lastLine(String text) {
    final lines = text.trim().split('\n');
    return lines.isEmpty ? '' : lines.last;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    cancel();
    super.dispose();
  }
}

enum LinuxState { idle, preparing, ready, error }

String humanBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  final power = (math.log(bytes) / math.log(1024)).floor().clamp(0, 3);
  final value = bytes / math.pow(1024, power);
  return '${value.toStringAsFixed(value >= 10 || power == 0 ? 0 : 1)} ${units[power]}';
}
