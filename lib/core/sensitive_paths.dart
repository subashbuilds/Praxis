/// Paths that must never be sent to a model as project context.
///
/// The project tree in the system prompt used to include every hidden file.
/// These checks keep `.env*`, private keys and credentials out of both the
/// tree and the richer prefetch context.
library;

const _ignoredDirectories = {
  '.git',
  '.praxis',
  '.dart_tool',
  '.gradle',
  '.idea',
  '.vscode',
  'node_modules',
  'build',
  'dist',
  'out',
  'coverage',
  '.next',
  '.nuxt',
  '.svelte-kit',
  'target',
  'vendor',
};

const _secretNames = {
  '.env',
  '.npmrc',
  '.netrc',
  '.git-credentials',
  '.htpasswd',
  'credentials',
  'credentials.json',
  'secrets',
  'secrets.json',
  'id_rsa',
  'id_dsa',
  'id_ecdsa',
  'id_ed25519',
};

const _secretSuffixes = {
  '.pem',
  '.key',
  '.p12',
  '.pfx',
  '.jks',
  '.keystore',
};

bool isIgnoredPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();
  if (parts.any(_ignoredDirectories.contains)) return true;
  if (parts.any((part) => part == '.env' || part.startsWith('.env.'))) {
    return true;
  }
  final name = parts.isEmpty ? '' : parts.last.toLowerCase();
  if (_secretNames.contains(name)) return true;
  if (_secretSuffixes.any(name.endsWith)) return true;
  if (name.startsWith('secret') &&
      (name.endsWith('.json') ||
          name.endsWith('.yaml') ||
          name.endsWith('.yml') ||
          name.endsWith('.toml'))) {
    return true;
  }
  return false;
}

/// A narrower check for files whose contents are likely to contain a secret,
/// even when the filename is not one of the obvious credential names.
bool looksLikeSecret(String path) {
  if (isIgnoredPath(path)) return true;
  final name = path.split('/').last.toLowerCase();
  return name.contains('credential') ||
      name.contains('api_key') ||
      name.contains('apikey') ||
      name.contains('access_token') ||
      name.contains('private_key');
}
