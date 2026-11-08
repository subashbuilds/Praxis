import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/linux_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('extracts a bootable Alpine rootfs from the bundled archive', () async {
    final base = await Directory.systemTemp.createTemp('praxis-linux-test-');
    final linux = LinuxEnvironment(base: base, assets: rootBundle);
    addTearDown(() async {
      linux.dispose();
      if (await base.exists()) await base.delete(recursive: true);
    });

    await linux.prepare();

    expect(linux.state, LinuxState.ready, reason: linux.error);
    final shell = File('${linux.rootfsPath}/bin/sh');
    final busybox = File('${linux.rootfsPath}/bin/busybox');
    expect(await shell.exists(), isTrue);
    expect(await busybox.exists(), isTrue);
    expect(await shell.length(), greaterThan(0));
    expect(await busybox.length(), greaterThan(0));
    expect(await File('${linux.rootfsPath}/.praxis-ready').exists(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
