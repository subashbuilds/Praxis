import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/cloudflare_routing.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';

void main() {
  test('partial node_modules is cleaned before an integration deploy build',
      () async {
    final temp = await Directory.systemTemp.createTemp('praxis_clean_install_');
    addTearDown(() => temp.delete(recursive: true));
    final state = AppState(
      root: temp,
      store: MemoryStore(),
      seedWelcome: false,
    );
    addTearDown(state.dispose);
    await state.init();
    final project =
        await state.createProject('partial-install', ProjectKind.node);
    final fs = state.fsFor(project);

    await fs.write(
      'package.json',
      jsonEncode({
        'name': 'partial-install',
        'private': true,
        'scripts': {'build': 'echo build'},
      }),
    );
    // This is what a timed-out npm install can leave behind: a folder without
    // npm's hidden lockfile and without the app's completion marker.
    await fs.write('node_modules/partial-package/index.js', 'incomplete');

    // SystemShell already puts <project>/.local/bin first on PATH. A real
    // executable stub exercises the production command path without faking
    // the shell itself.
    final stub = File(fs.absolute('.local/bin/npm'));
    await stub.parent.create(recursive: true);
    await stub.writeAsString('''#!/bin/sh
set -eu
printf 'npm %s\\n' "\$*" >> "\$PWD/.praxis/test-npm.log"
case "\$1" in
  install|ci|i)
    if [ -e node_modules/partial-package ]; then
      echo "partial install was not removed" >&2
      exit 2
    fi
    mkdir -p node_modules
    printf '{}' > node_modules/.package-lock.json
    printf 'installed' > node_modules/installed.txt
    echo "added 1 package"
    ;;
  run)
    mkdir -p dist
    printf '<html>built</html>' > dist/index.html
    echo "build complete"
    ;;
  *)
    echo "unexpected npm command: \$*" >&2
    exit 2
    ;;
esac
''');
    await Process.run('chmod', ['+x', stub.path]);

    final files = await state.prepareCloudflareFilesForTest(project);

    final log = await fs.read('.praxis/test-npm.log');
    expect(log.trim().split('\n'), [
      cloudflareNpmInstallCommand,
      cloudflareNpmBuildCommand,
    ]);
    expect(await fs.exists('node_modules/partial-package/index.js'), isFalse);
    expect(await fs.read('node_modules/installed.txt'), 'installed');
    expect(await fs.exists('.praxis/npm-install.json'), isTrue);
    expect(files.map((file) => file.path), contains('index.html'));
  });
}
