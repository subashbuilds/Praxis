import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package_cache.dart';
import 'vfs.dart';

enum DependencyEcosystem { node, python, none }

extension DependencyEcosystemX on DependencyEcosystem {
  String get label => switch (this) {
        DependencyEcosystem.node => 'Node.js',
        DependencyEcosystem.python => 'Python',
        DependencyEcosystem.none => 'No package manifest',
      };
}

enum DependencyIssueLevel { info, warning, error }

enum DependencyFix { cleanInstall, installRuntime, repairCache, none }

class DependencyIssue {
  const DependencyIssue({
    required this.title,
    required this.detail,
    this.level = DependencyIssueLevel.warning,
    this.fix = DependencyFix.none,
  });

  final String title;
  final String detail;
  final DependencyIssueLevel level;
  final DependencyFix fix;
}

class InstalledDependency {
  const InstalledDependency({
    required this.name,
    required this.version,
    this.direct = false,
    this.scope = '',
  });

  final String name;
  final String version;
  final bool direct;
  final String scope;
}

class DependencyReport {
  const DependencyReport({
    required this.ecosystem,
    required this.manager,
    required this.lockfile,
    required this.runtimeLabel,
    required this.runtimeReady,
    required this.installed,
    required this.issues,
    required this.projectBytes,
    required this.installBytes,
    required this.partialInstall,
    required this.mixedManagers,
    required this.nativePackages,
    required this.repairCommand,
    required this.cacheCommand,
    this.runtimeVersion = '',
    this.checkedAt,
  });

  final DependencyEcosystem ecosystem;
  final String manager;
  final String lockfile;
  final String runtimeLabel;
  final String runtimeVersion;
  final bool runtimeReady;
  final List<InstalledDependency> installed;
  final List<DependencyIssue> issues;
  final int projectBytes;
  final int installBytes;
  final bool partialInstall;
  final bool mixedManagers;
  final List<String> nativePackages;
  final String repairCommand;
  final String cacheCommand;
  final DateTime? checkedAt;

  int get packageCount => installed.length;
  int get directCount => installed.where((item) => item.direct).length;
  bool get hasEcosystem => ecosystem != DependencyEcosystem.none;
  bool get healthy => hasEcosystem && issues.isEmpty;

  String get summary {
    if (!hasEcosystem) return 'No package manifest';
    if (issues.isEmpty) return 'Dependencies look healthy';
    final errors = issues
        .where((issue) => issue.level == DependencyIssueLevel.error)
        .length;
    if (errors > 0) {
      return '$errors issue${errors == 1 ? '' : 's'} need attention';
    }
    return '${issues.length} suggestion${issues.length == 1 ? '' : 's'}';
  }
}

class DependencyAudit {
  const DependencyAudit({
    this.latest = const {},
    this.severities = const {},
    this.totalVulnerabilities = 0,
    this.error = '',
    this.checkedAt,
  });

  final Map<String, String> latest;
  final Map<String, String> severities;
  final int totalVulnerabilities;
  final String error;
  final DateTime? checkedAt;

  int get outdatedCount => latest.length;
  bool get hasData => checkedAt != null;
}

/// Reads package manifests and installed metadata without running a package
/// manager. Network checks (outdated versions and advisories) are deliberately
/// separate so opening the sheet stays fast and works offline.
Future<DependencyReport> inspectDependencies(
  ProjectFs fs, {
  bool nodeProject = false,
  bool pythonProject = false,
  bool nodeRuntimeReady = true,
  String nodeRuntimeVersion = '',
  bool pythonRuntimeReady = true,
  String pythonRuntimeVersion = '',
}) async {
  final hasPackageJson = await fs.exists('package.json');
  final pythonMarkers = <String>[
    'requirements.txt',
    'pyproject.toml',
    'Pipfile',
    'poetry.lock',
    'uv.lock',
  ];
  final pythonFiles = <String>[];
  for (final marker in pythonMarkers) {
    if (await fs.exists(marker)) pythonFiles.add(marker);
  }
  final node = nodeProject || hasPackageJson;
  final python =
      !node && (pythonProject || pythonFiles.contains('requirements.txt'));

  if (!node && !python) {
    return DependencyReport(
      ecosystem: DependencyEcosystem.none,
      manager: '',
      lockfile: '',
      runtimeLabel: '',
      runtimeReady: true,
      installed: const [],
      issues: const [],
      projectBytes: 0,
      installBytes: 0,
      partialInstall: false,
      mixedManagers: false,
      nativePackages: const [],
      repairCommand: '',
      cacheCommand: '',
      checkedAt: DateTime.now(),
    );
  }

  return node
      ? _inspectNode(
          fs,
          runtimeReady: nodeRuntimeReady,
          runtimeVersion: nodeRuntimeVersion,
        )
      : _inspectPython(
          fs,
          files: pythonFiles,
          runtimeReady: pythonRuntimeReady,
          runtimeVersion: pythonRuntimeVersion,
        );
}

Future<DependencyReport> _inspectNode(
  ProjectFs fs, {
  required bool runtimeReady,
  required String runtimeVersion,
}) async {
  final issues = <DependencyIssue>[];
  final lockManagers = <String, String>{
    'package-lock.json': 'npm',
    'npm-shrinkwrap.json': 'npm',
    'yarn.lock': 'yarn',
    'pnpm-lock.yaml': 'pnpm',
    'bun.lockb': 'bun',
    'bun.lock': 'bun',
  };
  final locks = <String>[];
  for (final entry in lockManagers.entries) {
    if (await fs.exists(entry.key)) locks.add(entry.key);
  }
  final manager = locks.isEmpty ? 'npm' : lockManagers[locks.first]!;
  final lockfile = locks.isEmpty ? '' : locks.join(', ');
  final mixed = locks.map((lock) => lockManagers[lock]).toSet().length > 1;
  final hasNodeModules = await fs.exists('node_modules');
  final hasHiddenLock = await fs.exists('node_modules/.package-lock.json');
  var partial = hasNodeModules && !hasHiddenLock;

  String packageJson = '';
  Map<String, dynamic> manifest = const {};
  try {
    packageJson = await fs.read('package.json');
    final decoded = jsonDecode(packageJson);
    if (decoded is Map) manifest = decoded.cast<String, dynamic>();
  } catch (_) {
    issues.add(const DependencyIssue(
      title: 'package.json could not be read',
      detail: 'Fix the JSON syntax before installing dependencies.',
      level: DependencyIssueLevel.error,
    ));
  }

  // The hidden lock is npm's record of what is physically installed. Prefer
  // it over the root lock, which can describe a newer or older resolution.
  // The root lock is the fallback when node_modules is absent or incomplete.
  final hiddenLock = await _firstReadable(fs, [
    'node_modules/.package-lock.json',
  ]);
  final rootLock = await _firstReadable(fs, [
    'package-lock.json',
    'npm-shrinkwrap.json',
  ]);
  final lockJson = hiddenLock.trim().isNotEmpty ? hiddenLock : rootLock;
  final marker = await _readNpmMarker(fs);
  if (hasNodeModules && lockJson.isNotEmpty) {
    final lockText = await _firstReadable(fs, [
      'package-lock.json',
      'npm-shrinkwrap.json',
    ]);
    if (packageJson.isNotEmpty && lockText.isNotEmpty) {
      final fingerprint = _digest('$packageJson\n$lockText');
      final reusable = npmInstallReusable(
        hasNodeModules: hasNodeModules,
        hasNpmLock: hasHiddenLock,
        markerFingerprint: marker,
        fingerprint: fingerprint,
      );
      if (!reusable && hasHiddenLock) {
        partial = true;
      }
    }
  }

  final direct = <String>{};
  for (final key in const [
    'dependencies',
    'devDependencies',
    'peerDependencies',
    'optionalDependencies',
  ]) {
    final value = manifest[key];
    if (value is Map) direct.addAll(value.keys.map((name) => '$name'));
  }
  final installed = _parseLockPackages(lockJson, direct);
  final nativePackages = _nativePackages({
    ...direct,
    ...installed.map((item) => item.name),
  });

  if (mixed) {
    issues.add(DependencyIssue(
      title: 'Mixed lockfiles',
      detail: 'Found $lockfile. Keep one package manager so installs are '
          'reproducible.',
      level: DependencyIssueLevel.error,
    ));
  } else if (locks.isEmpty) {
    issues.add(const DependencyIssue(
      title: 'No lockfile',
      detail: 'npm will resolve different versions on each install. Commit a '
          'package-lock.json after a clean install.',
    ));
  }
  if (partial) {
    issues.add(const DependencyIssue(
      title: 'Incomplete install',
      detail: 'node_modules exists without a complete npm lock, or the '
          'manifest changed after the last install. A clean install will '
          'remove the partial folder and reinstall.',
      level: DependencyIssueLevel.error,
      fix: DependencyFix.cleanInstall,
    ));
  }
  if (!runtimeReady) {
    issues.add(const DependencyIssue(
      title: 'Node.js runtime is missing',
      detail: 'Install Node.js and npm from the Linux environment before '
          'installing packages.',
      level: DependencyIssueLevel.error,
      fix: DependencyFix.installRuntime,
    ));
  }
  if (nativePackages.isNotEmpty) {
    issues.add(DependencyIssue(
      title: 'Native packages detected',
      detail: '${nativePackages.take(4).join(', ')} may need native binaries. '
          'If installation fails, replace them with a pure JavaScript '
          'alternative or a remote service.',
      level: DependencyIssueLevel.info,
    ));
  }

  final installBytes = hasNodeModules
      ? await directoryBytes(Directory(fs.absolute('node_modules')))
      : 0;
  final projectBytes =
      await directoryBytes(fs.root, skipTopLevel: const {'node_modules'}) +
          installBytes;
  if (installBytes > 500 * 1024 * 1024) {
    issues.add(DependencyIssue(
      title: 'Large dependency install',
      detail: 'node_modules uses ${_size(installBytes)}. Remove unused '
          'packages or reinstall to reclaim space.',
      level: DependencyIssueLevel.warning,
      fix: DependencyFix.cleanInstall,
    ));
  }
  if (projectBytes > 2 * 1024 * 1024 * 1024) {
    issues.add(const DependencyIssue(
      title: 'Disk pressure',
      detail: 'This project is over 2 GB. Clear package caches or generated '
          'folders before the next build.',
      level: DependencyIssueLevel.warning,
      fix: DependencyFix.repairCache,
    ));
  }

  return DependencyReport(
    ecosystem: DependencyEcosystem.node,
    manager: manager,
    lockfile: lockfile,
    runtimeLabel: 'Node.js',
    runtimeVersion: runtimeVersion,
    runtimeReady: runtimeReady,
    installed: installed,
    issues: issues,
    projectBytes: projectBytes,
    installBytes: installBytes,
    partialInstall: partial,
    mixedManagers: mixed,
    nativePackages: nativePackages,
    repairCommand: _nodeRepairCommand(manager, locks),
    cacheCommand: _nodeCacheCommand(manager),
    checkedAt: DateTime.now(),
  );
}

Future<DependencyReport> _inspectPython(
  ProjectFs fs, {
  required List<String> files,
  required bool runtimeReady,
  required String runtimeVersion,
}) async {
  final issues = <DependencyIssue>[];
  final hasRequirements = files.contains('requirements.txt');
  final hasPipfile = files.contains('Pipfile');
  final hasPoetry =
      files.contains('poetry.lock') || files.contains('pyproject.toml');
  final manager = hasPipfile
      ? 'pipenv'
      : hasPoetry
          ? 'poetry/pip'
          : 'pip';
  final mixedManagers = (hasPipfile ? 1 : 0) +
          (files.contains('poetry.lock') ? 1 : 0) +
          (files.contains('uv.lock') ? 1 : 0) >
      1;

  final venv = await _firstDirectory(fs, ['.venv', 'venv']);
  final installed =
      venv.isEmpty ? <InstalledDependency>[] : await _pythonPackages(fs, venv);
  final directNames = hasRequirements
      ? await _requirementsNames(fs, 'requirements.txt')
      : <String>{};

  if (venv.isEmpty && (hasRequirements || hasPoetry)) {
    issues.add(const DependencyIssue(
      title: 'No virtual environment',
      detail: 'Create .venv and install the project requirements so packages '
          'do not collide with the system Python.',
      fix: DependencyFix.cleanInstall,
    ));
  }
  if (mixedManagers) {
    issues.add(DependencyIssue(
      title: 'Mixed Python managers',
      detail: 'Found ${files.join(', ')}. Choose one workflow for repeatable '
          'installs.',
      level: DependencyIssueLevel.error,
    ));
  }
  if (!runtimeReady) {
    issues.add(const DependencyIssue(
      title: 'Python runtime is missing',
      detail: 'Install Python 3 from the Linux environment before installing '
          'project packages.',
      level: DependencyIssueLevel.error,
      fix: DependencyFix.installRuntime,
    ));
  }
  if (!hasRequirements && files.contains('pyproject.toml')) {
    issues.add(const DependencyIssue(
      title: 'No requirements file',
      detail: 'Project metadata was found, but there is no requirements.txt to '
          'reproduce the installed set.',
      level: DependencyIssueLevel.info,
    ));
  }

  final installBytes =
      venv.isEmpty ? 0 : await directoryBytes(Directory(fs.absolute(venv)));
  final projectBytes =
      await directoryBytes(fs.root, skipTopLevel: const {'.venv', 'venv'}) +
          installBytes;
  if (installBytes > 500 * 1024 * 1024) {
    issues.add(DependencyIssue(
      title: 'Large environment',
      detail: '$venv uses ${_size(installBytes)}. Remove unused packages to '
          'reclaim space.',
      fix: DependencyFix.cleanInstall,
    ));
  }
  if (projectBytes > 2 * 1024 * 1024 * 1024) {
    issues.add(const DependencyIssue(
      title: 'Disk pressure',
      detail: 'This project is over 2 GB. Clear the pip cache before the next '
          'install.',
      level: DependencyIssueLevel.warning,
      fix: DependencyFix.repairCache,
    ));
  }

  return DependencyReport(
    ecosystem: DependencyEcosystem.python,
    manager: manager,
    lockfile: files.join(', '),
    runtimeLabel: 'Python',
    runtimeVersion: runtimeVersion,
    runtimeReady: runtimeReady,
    installed: _sortPackages(installed, directNames),
    issues: issues,
    projectBytes: projectBytes,
    installBytes: installBytes,
    partialInstall: venv.isEmpty && (hasRequirements || hasPoetry),
    mixedManagers: mixedManagers,
    nativePackages: const [],
    repairCommand: hasPipfile
        ? 'pipenv install --deploy'
        : hasRequirements
            ? venv.isNotEmpty
                ? '$venv/bin/python -m pip install -r requirements.txt'
                : 'python3 -m venv .venv && .venv/bin/pip install -r requirements.txt'
            : files.contains('pyproject.toml')
                ? venv.isNotEmpty
                    ? '$venv/bin/python -m pip install -e .'
                    : 'python3 -m venv .venv && .venv/bin/pip install -e .'
                : '',
    cacheCommand: 'python3 -m pip cache purge',
    checkedAt: DateTime.now(),
  );
}

String _digest(String text) => sha256.convert(utf8.encode(text)).toString();

Future<String> _firstReadable(ProjectFs fs, List<String> paths) async {
  for (final path in paths) {
    try {
      if (await fs.exists(path)) {
        final text = await fs.read(path);
        if (text.trim().isNotEmpty) return text;
      }
    } catch (_) {}
  }
  return '';
}

Future<String> _firstDirectory(ProjectFs fs, List<String> paths) async {
  for (final path in paths) {
    if (await fs.isDirectory(path)) return path;
  }
  return '';
}

Future<String?> _readNpmMarker(ProjectFs fs) async {
  try {
    final raw = jsonDecode(await fs.read('.praxis/npm-install.json'));
    if (raw is Map) return raw['fingerprint'] as String?;
  } catch (_) {}
  return null;
}

List<InstalledDependency> _parseLockPackages(
  String raw,
  Set<String> direct,
) {
  if (raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final packages = decoded['packages'];
    final found = <String, InstalledDependency>{};
    if (packages is Map) {
      for (final entry in packages.entries) {
        final path = '${entry.key}';
        if (path.isEmpty || !path.contains('node_modules/')) continue;
        final value = entry.value;
        if (value is! Map) continue;
        final name = path.split('node_modules/').last;
        if (name.isEmpty) continue;
        final version = value['version'] as String? ?? '';
        if (version.isEmpty) continue;
        final key = '$name@$version';
        final scope = value['dev'] == true
            ? 'dev'
            : value['optional'] == true
                ? 'optional'
                : '';
        found[key] = InstalledDependency(
          name: name,
          version: version,
          direct: direct.contains(name),
          scope: scope,
        );
      }
    } else {
      final dependencies = decoded['dependencies'];
      if (dependencies is Map) {
        _walkOldLock(dependencies, direct, found, '');
      }
    }
    return _sortPackages(found.values.toList(), direct);
  } catch (_) {
    return const [];
  }
}

void _walkOldLock(
  Map<dynamic, dynamic> dependencies,
  Set<String> direct,
  Map<String, InstalledDependency> found,
  String scope,
) {
  for (final entry in dependencies.entries) {
    final name = '${entry.key}';
    final value = entry.value;
    if (name.isEmpty || value is! Map) continue;
    final version = value['version'] as String? ?? '';
    final nextScope = value['dev'] == true ? 'dev' : scope;
    if (version.isNotEmpty) {
      found['$name@$version'] = InstalledDependency(
        name: name,
        version: version,
        direct: direct.contains(name),
        scope: nextScope,
      );
    }
    final nested = value['dependencies'];
    if (nested is Map) _walkOldLock(nested, direct, found, nextScope);
  }
}

List<InstalledDependency> _sortPackages(
  List<InstalledDependency> packages,
  Set<String> direct,
) {
  final sorted = packages
      .map((item) => InstalledDependency(
            name: item.name,
            version: item.version,
            direct: item.direct || direct.contains(item.name),
            scope: item.scope,
          ))
      .toList()
    ..sort((a, b) {
      if (a.direct != b.direct) return a.direct ? -1 : 1;
      return a.name.compareTo(b.name);
    });
  return sorted;
}

Future<List<InstalledDependency>> _pythonPackages(
  ProjectFs fs,
  String venv,
) async {
  final found = <String, InstalledDependency>{};
  final site = Directory('${fs.absolute(venv)}/lib');
  if (!await site.exists()) return const [];
  await for (final pythonDir in site.list(followLinks: false)) {
    if (pythonDir is! Directory) continue;
    final packages = Directory('${pythonDir.path}/site-packages');
    if (!await packages.exists()) continue;
    await for (final entity in packages.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.path.split('/').last;
      if (!name.endsWith('.dist-info') && !name.endsWith('.egg-info')) {
        continue;
      }
      final metadata = File('${entity.path}/METADATA');
      final pkgInfo = File('${entity.path}/PKG-INFO');
      final source = await metadata.exists()
          ? metadata
          : await pkgInfo.exists()
              ? pkgInfo
              : null;
      if (source == null) continue;
      final lines = await source.readAsLines();
      var package = '';
      var version = '';
      for (final line in lines) {
        if (line.toLowerCase().startsWith('name:')) {
          package = line.substring(5).trim();
        } else if (line.toLowerCase().startsWith('version:')) {
          version = line.substring(8).trim();
        }
        if (package.isNotEmpty && version.isNotEmpty) break;
      }
      if (package.isEmpty || version.isEmpty) continue;
      found['$package@$version'] = InstalledDependency(
        name: package,
        version: version,
        direct: false,
      );
    }
  }
  return found.values.toList();
}

Future<Set<String>> _requirementsNames(ProjectFs fs, String path) async {
  final names = <String>{};
  try {
    for (final raw in (await fs.read(path)).split('\n')) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty || line.startsWith('-')) continue;
      final match = RegExp(r'^([A-Za-z0-9_.-]+)').firstMatch(line);
      if (match != null) names.add(match.group(1)!);
    }
  } catch (_) {}
  return names;
}

List<String> _nativePackages(Set<String> names) {
  const known = {
    'sharp',
    'better-sqlite3',
    'canvas',
    'node-gyp',
    'node-sass',
    'sqlite3',
    'bcrypt',
    'puppeteer',
    'playwright',
    '@playwright/test',
    '@napi-rs/canvas',
  };
  final result = <String>[];
  for (final name in names) {
    if (known.contains(name) || name.contains('workerd')) result.add(name);
  }
  result.sort();
  return result;
}

String _nodeRepairCommand(String manager, List<String> locks) {
  if (manager == 'yarn') return 'yarn install --frozen-lockfile';
  if (manager == 'pnpm') return 'pnpm install --frozen-lockfile';
  if (manager == 'bun') return 'bun install --frozen-lockfile';
  return locks.contains('package-lock.json') ||
          locks.contains('npm-shrinkwrap.json')
      ? 'npm ci --no-audit --no-fund'
      : 'npm install --no-audit --no-fund';
}

String _nodeCacheCommand(String manager) => switch (manager) {
      'yarn' => 'yarn cache clean',
      'pnpm' => 'pnpm store prune',
      'bun' => 'bun pm cache rm',
      _ => 'npm cache verify',
    };

Future<int> directoryBytes(
  Directory directory, {
  Set<String> skipTopLevel = const {},
}) async {
  if (!await directory.exists()) return 0;
  return _directoryBytes(directory, skipTopLevel, 0);
}

Future<int> _directoryBytes(
  Directory directory,
  Set<String> skipTopLevel,
  int depth,
) async {
  var total = 0;
  try {
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.path.split('/').last;
      if (entity is Directory) {
        if (depth == 0 && skipTopLevel.contains(name)) continue;
        total += await _directoryBytes(entity, const {}, depth + 1);
      } else if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

bool isDependencyName(String name) =>
    RegExp(r'^(@[a-z0-9._-]+/)?[a-z0-9._-]+$').hasMatch(name);

Map<String, dynamic>? _jsonObject(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

Map<String, String> parseNpmOutdated(String raw) {
  try {
    final decoded = _jsonObject(raw);
    if (decoded == null) return const {};
    final result = <String, String>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is Map) {
        final latest = value['latest'] as String? ?? '';
        if (latest.isNotEmpty) result[entry.key] = latest;
      }
    }
    return result;
  } catch (_) {
    return const {};
  }
}

DependencyAudit parseNpmAudit(String raw) {
  try {
    final decoded = _jsonObject(raw);
    if (decoded == null) return const DependencyAudit();
    final severities = <String, String>{};
    final vulnerabilities = decoded['vulnerabilities'];
    if (vulnerabilities is Map) {
      for (final entry in vulnerabilities.entries) {
        final value = entry.value;
        if (value is Map) {
          severities['${entry.key}'] =
              value['severity'] as String? ?? 'unknown';
        }
      }
    }
    var total = severities.length;
    final metadata = decoded['metadata'];
    if (metadata is Map) {
      final counts = metadata['vulnerabilities'];
      if (counts is Map) {
        final reported = counts['total'];
        if (reported is int) total = reported;
      }
    }
    return DependencyAudit(
      severities: severities,
      totalVulnerabilities: total,
      checkedAt: DateTime.now(),
    );
  } catch (_) {
    return const DependencyAudit();
  }
}
