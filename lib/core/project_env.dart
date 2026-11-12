import 'dart:convert';

import 'vfs.dart';

/// One project environment entry. Secret values are kept on the device and are
/// never included in the agent prompt; only the name is visible to it.
class ProjectEnvEntry {
  const ProjectEnvEntry({
    required this.name,
    required this.value,
    this.secret = false,
  });

  final String name;
  final String value;
  final bool secret;

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'secret': secret,
      };

  static ProjectEnvEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'] as String? ?? '';
    if (!isValidName(name)) return null;
    return ProjectEnvEntry(
      name: name,
      value: json['value'] as String? ?? '',
      secret: json['secret'] == true,
    );
  }

  static bool isValidName(String name) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name.trim());
}

/// Lives at `.praxis/environment.json`, outside the project tree the agent
/// browses. Values are used for build and shell commands but never printed into
/// the conversation.
class ProjectEnvStore {
  const ProjectEnvStore._();

  static const path = '.praxis/environment.json';

  static Future<List<ProjectEnvEntry>> load(ProjectFs fs) async {
    try {
      if (!await fs.exists(path)) return const [];
      final decoded = jsonDecode(await fs.read(path));
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (ProjectEnvEntry.fromJson(item) case final entry?) entry,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(
    ProjectFs fs,
    List<ProjectEnvEntry> entries,
  ) =>
      fs.write(
        path,
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      );

  static Map<String, String> values(List<ProjectEnvEntry> entries) => {
        for (final entry in entries)
          if (entry.name.trim().isNotEmpty) entry.name.trim(): entry.value,
      };
}
