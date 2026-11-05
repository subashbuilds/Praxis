import 'dart:io';

import 'vfs.dart';

/// One Claude-style skill installed under `.praxis/skills/<slug>/SKILL.md`.
class ProjectSkill {
  const ProjectSkill({
    required this.slug,
    required this.name,
    required this.description,
    required this.instructions,
    required this.size,
    required this.modifiedAt,
  });

  final String slug;
  final String name;
  final String description;
  final String instructions;
  final int size;
  final DateTime modifiedAt;

  String get folder => '.praxis/skills/$slug';
  String get path => '$folder/SKILL.md';
}

class ProjectSkillsStore {
  const ProjectSkillsStore._();

  static Directory folderFor(ProjectFs fs) =>
      Directory('${fs.rootPath}/.praxis/skills');

  static Future<List<ProjectSkill>> load(ProjectFs fs) async {
    final root = folderFor(fs);
    if (!await root.exists()) return const [];
    final skills = <ProjectSkill>[];
    final folders = await root.list(followLinks: false).toList();
    folders.sort((a, b) => a.path.compareTo(b.path));
    for (final entity in folders) {
      if (entity is! Directory || skills.length >= 50) continue;
      final slug = entity.path.split(Platform.pathSeparator).last;
      final file = File('${entity.path}/SKILL.md');
      if (!await file.exists()) continue;
      try {
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) continue;
        final parsed = parse(raw);
        final stat = await file.stat();
        skills.add(ProjectSkill(
          slug: slug,
          name: parsed.name.isEmpty ? _titleFromSlug(slug) : parsed.name,
          description: parsed.description,
          instructions: parsed.body,
          size: stat.size,
          modifiedAt: stat.modified,
        ));
      } catch (_) {
        // A broken skill should not hide the others.
      }
    }
    return skills;
  }

  static ({String name, String description, String body}) parse(String raw) {
    final frontMatter =
        RegExp(r'^---\r?\n([\s\S]*?)\r?\n---\r?\n?').firstMatch(raw);
    final meta = frontMatter?.group(1) ?? '';
    final name = RegExp(r'^name:\s*(.+)$', multiLine: true)
            .firstMatch(meta)
            ?.group(1)
            ?.trim() ??
        '';
    final description = RegExp(r'^description:\s*(.+)$', multiLine: true)
            .firstMatch(meta)
            ?.group(1)
            ?.trim() ??
        '';
    final body =
        (frontMatter == null ? raw : raw.substring(frontMatter.end)).trim();
    return (
      name: _unquote(name),
      description: _unquote(description),
      body: body
    );
  }

  static String _unquote(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  static String _titleFromSlug(String slug) => slug
      .split(RegExp(r'[-_]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
