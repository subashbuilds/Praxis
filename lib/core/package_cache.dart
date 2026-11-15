/// A node_modules folder is only reusable when npm finished its install (the
/// hidden lockfile exists) and the manifest has not changed since the marker
/// was written. A partial folder left by a timeout fails both checks.
bool npmInstallReusable({
  required bool hasNodeModules,
  required bool hasNpmLock,
  required String? markerFingerprint,
  required String fingerprint,
}) =>
    hasNodeModules &&
    hasNpmLock &&
    markerFingerprint != null &&
    markerFingerprint == fingerprint;

enum PackageCacheRuntime { npm, python }

extension PackageCacheRuntimeLabel on PackageCacheRuntime {
  String get label => switch (this) {
        PackageCacheRuntime.npm => 'npm',
        PackageCacheRuntime.python => 'Python',
      };
}

/// One package download kept by a package manager's shared cache. Keys are
/// the identifiers the manager needs to remove that download later.
class CachedPackage {
  const CachedPackage({
    required this.runtime,
    required this.name,
    required this.version,
    required this.keys,
  });

  final PackageCacheRuntime runtime;
  final String name;
  final String version;
  final List<String> keys;

  String get id => '${runtime.name}:$name@$version';
}

/// Extracts npm tarball cache keys. Metadata keys and the duplicate
/// `pacote:tarball:` entries are ignored; a package is listed once even when
/// npm stored more than one key for it.
List<CachedPackage> parseNpmCache(String output) {
  final grouped = <String, CachedPackage>{};
  final tarball = RegExp(
    r'https?://[^/\s]+/(.+?)/-/(?:[^/\s]+)-([^/\s]+)\.tgz\s*$',
    caseSensitive: false,
  );
  for (final raw in output.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final match = tarball.firstMatch(line);
    if (match == null) continue;
    final name = match.group(1) ?? '';
    final version = match.group(2) ?? '';
    if (name.isEmpty || version.isEmpty) continue;
    final id = '$name@$version';
    final existing = grouped[id];
    if (existing == null) {
      grouped[id] = CachedPackage(
        runtime: PackageCacheRuntime.npm,
        name: name,
        version: version,
        keys: [line],
      );
    } else if (!existing.keys.contains(line)) {
      grouped[id] = CachedPackage(
        runtime: existing.runtime,
        name: existing.name,
        version: existing.version,
        keys: [...existing.keys, line],
      );
    }
  }
  return grouped.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// Extracts wheel and source-archive filenames from `pip cache list
/// --format=abspath`. A package can have several cached builds; they share a
/// single row and keep every filename for deletion.
List<CachedPackage> parsePipCache(String output) {
  final grouped = <String, CachedPackage>{};
  for (final raw in output.split('\n')) {
    final path = raw.trim();
    if (path.isEmpty) continue;
    final filename = path.split('/').last;
    final archive = filename.endsWith('.whl') ||
        filename.endsWith('.tar.gz') ||
        filename.endsWith('.zip');
    if (!archive) continue;
    final stem = filename
        .replaceFirst(RegExp(r'\.whl$'), '')
        .replaceFirst(RegExp(r'\.tar\.gz$'), '')
        .replaceFirst(RegExp(r'\.zip$'), '');
    final match = RegExp(r'^(.+?)-([0-9][^-]*)(?:-|$)').firstMatch(stem);
    if (match == null) continue;
    final name = match.group(1) ?? '';
    final version = match.group(2) ?? '';
    if (name.isEmpty || version.isEmpty) continue;
    final id = '$name@$version';
    final existing = grouped[id];
    if (existing == null) {
      grouped[id] = CachedPackage(
        runtime: PackageCacheRuntime.python,
        name: name,
        version: version,
        keys: [filename],
      );
    } else if (!existing.keys.contains(filename)) {
      grouped[id] = CachedPackage(
        runtime: existing.runtime,
        name: existing.name,
        version: existing.version,
        keys: [...existing.keys, filename],
      );
    }
  }
  return grouped.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}
