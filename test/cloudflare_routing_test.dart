import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/cloudflare_routing.dart';
import 'package:praxis/core/vfs.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('praxis_deploy_');
    fs = ProjectFs(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('a static frontend deploys to Pages', () async {
    await fs.write('index.html', '<h1>Static</h1>');
    await fs.write('assets/app.js', 'console.log("ready");');

    final plan = await planCloudflareDeploy(fs);

    expect(plan.surface, CloudflareDeploySurface.pages);
    expect(plan.usesWorkers, isFalse);
    expect(plan.reason, contains('static frontend'));
  });

  test('a server entry deploys to Workers', () async {
    await fs.write('package.json', jsonEncode({'dependencies': {}}));
    await fs.write('server.js', 'console.log("api");');

    final plan = await planCloudflareDeploy(fs);

    expect(plan.surface, CloudflareDeploySurface.workers);
    expect(plan.usesWorkers, isTrue);
    expect(plan.reason, contains('server entry'));
  });

  test('API routes deploy to Workers', () async {
    await fs.write('package.json', jsonEncode({'dependencies': {}}));
    await fs.write('src/pages/api/health.ts', 'export default () => "ok";');

    final plan = await planCloudflareDeploy(fs);

    expect(plan.surface, CloudflareDeploySurface.workers);
    expect(plan.reason, contains('API routes'));
  });

  test('a server framework deploys to Workers', () async {
    await fs.write(
      'package.json',
      jsonEncode({
        'dependencies': {'express': '^4.0.0'},
      }),
    );

    final plan = await planCloudflareDeploy(fs);

    expect(plan.surface, CloudflareDeploySurface.workers);
    expect(plan.reason, contains('server framework'));
  });

  test('a Wrangler config deploy to Workers', () async {
    await fs.write('wrangler.toml', 'name = "api"\nmain = "src/index.ts"');
    await fs.write('src/index.ts', 'export default { fetch() {} };');

    final plan = await planCloudflareDeploy(fs);

    expect(plan.surface, CloudflareDeploySurface.workers);
    expect(plan.hasWrangler, isTrue);
  });

  test('Pages Functions stay on Pages', () async {
    await fs.write('index.html', '<h1>Functions</h1>');
    await fs.write(
        'functions/api/hello.ts', 'export const onRequest = () => {};');

    final plan = await planCloudflareDeploy(fs);

    expect(plan.surface, CloudflareDeploySurface.pages);
    expect(plan.hasPagesFunctions, isTrue);
    expect(plan.reason, contains('Pages Functions'));
  });

  test('npm build fixture exposes a build script and static dist output',
      () async {
    final package = jsonEncode({
      'scripts': {'build': 'vite build'},
      'dependencies': {'vite': '^5.0.0'},
    });
    await fs.write('package.json', package);
    await fs.write('dist/index.html', '<h1>Built</h1>');

    expect(hasNpmBuildScript(package), isTrue);
    expect(hasNpmBuildScript('{"scripts": {}}'), isFalse);
    expect(await staticOutputFolder(fs), 'dist');
    expect(cloudflareNpmInstallCommand,
        'npm install --prefer-offline --no-audit --no-fund');
    expect(cloudflareNpmBuildCommand, 'npm run build');
    expect(cloudflareWorkersUnavailable, contains('workerd'));
    expect(
      (await planCloudflareDeploy(fs)).surface,
      CloudflareDeploySurface.pages,
    );
  });
}
