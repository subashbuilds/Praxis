import 'dart:convert';

import 'vfs.dart';

/// The Cloudflare runtime a project needs. Pages serves static output; Workers
/// runs server code and bundling from a Wrangler config.
enum CloudflareDeploySurface { pages, workers }

class CloudflareDeployPlan {
  const CloudflareDeployPlan({
    required this.surface,
    required this.reason,
    this.hasWrangler = false,
    this.hasPagesFunctions = false,
  });

  final CloudflareDeploySurface surface;
  final String reason;
  final bool hasWrangler;
  final bool hasPagesFunctions;

  bool get usesWorkers => surface == CloudflareDeploySurface.workers;
}

const cloudflareNpmInstallCommand = 'npm install --no-audit --no-fund';
const cloudflareNpmBuildCommand = 'npm run build';

const _staticOutputCandidates = [
  'out',
  'dist',
  'build/web',
  'build',
  '.vercel/output/static',
];

/// Decides where a Cloudflare deploy belongs before any upload starts. This is
/// file-based on purpose: the deploy sheet can show the same answer the deploy
/// path will use.
Future<CloudflareDeployPlan> planCloudflareDeploy(ProjectFs fs) async {
  final entries = await fs.list(includeHidden: true);
  final paths = entries
      .map((entry) => entry.path.replaceAll('\\', '/'))
      .where((path) => !path.startsWith('node_modules/'))
      .toList();
  final hasWrangler = paths.any((path) => RegExp(
        r'^wrangler\.(toml|jsonc?)$',
        caseSensitive: false,
      ).hasMatch(path));
  final hasPagesFunctions = paths.any(
    (path) => path == '_worker.js' || path.startsWith('functions/'),
  );

  if (hasWrangler) {
    return const CloudflareDeployPlan(
      surface: CloudflareDeploySurface.workers,
      reason: 'A Wrangler config was found, so this deploy uses Workers.',
      hasWrangler: true,
    );
  }
  // Pages Functions are already a Pages runtime and must not be routed away.
  if (hasPagesFunctions) {
    return const CloudflareDeployPlan(
      surface: CloudflareDeploySurface.pages,
      reason: 'Pages Functions were found, so this deploy uses Pages.',
      hasPagesFunctions: true,
    );
  }
  if (paths.any((path) => RegExp(
        r'(^|/)(server|worker|backend)\.(js|ts|mjs|cjs)$',
        caseSensitive: false,
      ).hasMatch(path))) {
    return const CloudflareDeployPlan(
      surface: CloudflareDeploySurface.workers,
      reason: 'A server entry was found, so this deploy uses Workers.',
    );
  }
  if (paths.any((path) => RegExp(
        r'^(src/|pages/|src/pages/)?api/.*\.(js|ts|mjs|cjs|jsx|tsx)$|'
        r'^(src/)?app/api/.*\.(js|ts|mjs|cjs|jsx|tsx)$',
        caseSensitive: false,
      ).hasMatch(path))) {
    return const CloudflareDeployPlan(
      surface: CloudflareDeploySurface.workers,
      reason: 'API routes were found, so this deploy uses Workers.',
    );
  }
  if (paths.contains('package.json')) {
    try {
      final package = jsonDecode(await fs.read('package.json'));
      final dependencies = package is Map ? package['dependencies'] : null;
      final devDependencies =
          package is Map ? package['devDependencies'] : null;
      final deps = <String>{
        if (dependencies is Map) ...dependencies.keys.cast<String>(),
        if (devDependencies is Map) ...devDependencies.keys.cast<String>(),
      };
      const serverDeps = {
        'express',
        'koa',
        'fastify',
        '@nestjs/core',
        'hono',
        'nuxt',
      };
      if (deps.any(serverDeps.contains)) {
        return const CloudflareDeployPlan(
          surface: CloudflareDeploySurface.workers,
          reason: 'A server framework was found, so this deploy uses Workers.',
        );
      }
    } catch (_) {
      // The build path reports a malformed package file.
    }
  }
  return const CloudflareDeployPlan(
    surface: CloudflareDeploySurface.pages,
    reason: 'This is a static frontend, so this deploy uses Pages.',
  );
}

/// Pages Direct Upload can only serve files. A Node project without a root
/// entry point has to be built first.
bool hasNpmBuildScript(String packageJson) {
  try {
    final package = jsonDecode(packageJson);
    final scripts = package is Map ? package['scripts'] : null;
    return scripts is Map && scripts['build'] is String;
  } catch (_) {
    return false;
  }
}

/// Finds the folder a build wrote its static site into, relative to the project
/// root. The trailing `/index.html` is the signal that the output is servable.
Future<String?> staticOutputFolder(ProjectFs fs) async {
  for (final candidate in _staticOutputCandidates) {
    if (await fs.exists('$candidate/index.html')) return candidate;
  }
  return null;
}
