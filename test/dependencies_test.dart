import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/dependencies.dart';
import 'package:praxis/core/vfs.dart';

void main() {
  test('node diagnosis finds mixed lockfiles, a partial install and versions',
      () async {
    final temp = await Directory.systemTemp.createTemp('praxis_deps_');
    addTearDown(() => temp.delete(recursive: true));
    final fs = ProjectFs(temp);
    await fs.ensureRoot();
    await fs.write(
      'package.json',
      jsonEncode({
        'name': 'demo',
        'dependencies': {'left-pad': '^1.0.0', 'sharp': '^0.33.0'},
      }),
    );
    await fs.write(
      'package-lock.json',
      jsonEncode({
        'lockfileVersion': 3,
        'packages': {
          '': {'name': 'demo'},
          'node_modules/left-pad': {'version': '1.3.0'},
          'node_modules/sharp': {'version': '0.33.5'},
        },
      }),
    );
    await fs.write('yarn.lock', '# another manager');
    await fs.write('node_modules/left-pad/index.js', 'partial');

    final report = await inspectDependencies(
      fs,
      nodeProject: true,
      nodeRuntimeReady: false,
    );

    expect(report.ecosystem, DependencyEcosystem.node);
    expect(report.manager, 'npm');
    expect(report.mixedManagers, isTrue);
    expect(report.partialInstall, isTrue);
    expect(report.repairCommand, 'npm ci --no-audit --no-fund');
    expect(report.installed.map((item) => '${item.name}@${item.version}'),
        containsAll(['left-pad@1.3.0', 'sharp@0.33.5']));
    expect(report.installed.every((item) => item.direct), isTrue);
    expect(report.nativePackages, contains('sharp'));
    expect(
      report.issues.map((issue) => issue.title),
      containsAll(['Mixed lockfiles', 'Incomplete install']),
    );
    expect(
      report.issues.any((issue) =>
          issue.fix == DependencyFix.cleanInstall &&
          issue.title == 'Incomplete install'),
      isTrue,
    );
  });

  test('installed dependencies prefer the hidden node_modules lock', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_deps_');
    addTearDown(() => temp.delete(recursive: true));
    final fs = ProjectFs(temp);
    await fs.ensureRoot();
    final packageJson = jsonEncode({
      'name': 'demo',
      'dependencies': {'left-pad': '^2.0.0'},
    });
    final rootLock = jsonEncode({
      'lockfileVersion': 3,
      'packages': {
        '': {'name': 'demo'},
        'node_modules/left-pad': {'version': '1.3.0'},
      },
    });
    await fs.write('package.json', packageJson);
    // The root lock describes the requested install; the hidden lock records
    // what npm actually put on disk. They disagree here on purpose.
    await fs.write('package-lock.json', rootLock);
    await fs.write(
      '.praxis/npm-install.json',
      jsonEncode({
        'fingerprint':
            sha256.convert(utf8.encode('$packageJson\n$rootLock')).toString(),
      }),
    );
    await fs.write(
      'node_modules/.package-lock.json',
      jsonEncode({
        'lockfileVersion': 3,
        'packages': {
          'node_modules/left-pad': {'version': '2.0.0'},
        },
      }),
    );
    await fs.write('node_modules/left-pad/package.json', '{}');

    final report = await inspectDependencies(fs, nodeProject: true);

    expect(
      report.installed.map((item) => '${item.name}@${item.version}'),
      ['left-pad@2.0.0'],
    );
    expect(report.partialInstall, isFalse);
  });

  test('incomplete node_modules falls back to the root lock', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_deps_');
    addTearDown(() => temp.delete(recursive: true));
    final fs = ProjectFs(temp);
    await fs.ensureRoot();
    await fs.write(
      'package.json',
      jsonEncode({
        'name': 'demo',
        'dependencies': {'left-pad': '^1.0.0'},
      }),
    );
    await fs.write(
      'package-lock.json',
      jsonEncode({
        'lockfileVersion': 3,
        'packages': {
          '': {'name': 'demo'},
          'node_modules/left-pad': {'version': '1.3.0'},
        },
      }),
    );
    await fs.write('node_modules/left-pad/index.js', 'partial');

    final report = await inspectDependencies(fs, nodeProject: true);

    expect(
      report.installed.map((item) => '${item.name}@${item.version}'),
      ['left-pad@1.3.0'],
    );
    expect(report.partialInstall, isTrue);
  });

  test('parse registry output without trusting exit status', () {
    final outdated = parseNpmOutdated(jsonEncode({
      'left-pad': {'current': '1.0.0', 'latest': '1.3.0'},
    }));
    final audit = parseNpmAudit(jsonEncode({
      'vulnerabilities': {
        'left-pad': {'severity': 'high'},
      },
      'metadata': {
        'vulnerabilities': {'total': 3},
      },
    }));

    expect(outdated, {'left-pad': '1.3.0'});
    expect(audit.severities, {'left-pad': 'high'});
    expect(audit.totalVulnerabilities, 3);
  });
}
