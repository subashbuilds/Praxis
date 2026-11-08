import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'integrations.dart';
import 'project_skills.dart';

/// A repository returned by GitHub's public repository search.
class SkillRepository {
  const SkillRepository({
    required this.owner,
    required this.name,
    required this.description,
    required this.stars,
    required this.branch,
  });

  final String owner;
  final String name;
  final String description;
  final int stars;
  final String branch;

  String get fullName => '$owner/$name';
}

/// One `SKILL.md` found inside a repository.
class DiscoveredSkill {
  const DiscoveredSkill({
    required this.repository,
    required this.path,
    required this.name,
    required this.description,
  });

  final SkillRepository repository;
  final String path;
  final String name;
  final String description;
}

/// GitHub's public REST API is free for anonymous use. Search accepts a
/// repository query and the tree endpoint lists every SKILL.md at once, so a
/// discovery round costs one request for search and one per opened repository.
class SkillDiscovery {
  SkillDiscovery({required this.client, this.token = ''});

  final http.Client client;
  final String token;

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Praxis',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<List<SkillRepository>> search(String query) async {
    final cleaned = query.trim();
    final q = cleaned.isEmpty
        ? 'claude skills in:name,description,readme'
        : '$cleaned skill in:name,description,readme';
    final uri = Uri.https('api.github.com', '/search/repositories', {
      'q': q,
      'sort': 'stars',
      'order': 'desc',
      'per_page': '12',
    });
    final response = await client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw IntegrationException(
        'GitHub is rate-limiting discovery. Add a GitHub token in '
        'Integrations, or try again later.',
      );
    }
    if (response.statusCode != 200) {
      throw IntegrationException(
          'GitHub search failed (HTTP ${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = body['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map)
          SkillRepository(
            owner: (item['owner'] as Map?)?['login'] as String? ?? '',
            name: item['name'] as String? ?? '',
            description: item['description'] as String? ?? '',
            stars: item['stargazers_count'] as int? ?? 0,
            branch: item['default_branch'] as String? ?? 'main',
          ),
    ].where((repo) => repo.owner.isNotEmpty && repo.name.isNotEmpty).toList();
  }

  Future<List<DiscoveredSkill>> skillsIn(SkillRepository repo) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/${repo.owner}/${repo.name}/git/trees/${Uri.encodeComponent(repo.branch)}',
      {'recursive': '1'},
    );
    final response = await client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 45));
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw IntegrationException(
          'GitHub is rate-limiting discovery. Try again later.');
    }
    if (response.statusCode != 200) {
      throw IntegrationException(
          'Could not read ${repo.fullName} (HTTP ${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final tree = body['tree'];
    if (tree is! List) return const [];
    final found = <DiscoveredSkill>[];
    for (final item in tree) {
      if (item is! Map) continue;
      final path = item['path'] as String? ?? '';
      if (path.isEmpty || (item['type'] as String?) != 'blob') continue;
      final lower = path.toLowerCase();
      if (!lower.endsWith('skill.md')) continue;
      if (lower.contains('node_modules/') || lower.startsWith('.git/')) {
        continue;
      }
      final parts = path.split('/');
      final slug = parts.length > 1 ? parts[parts.length - 2] : repo.name;
      found.add(DiscoveredSkill(
        repository: repo,
        path: path,
        name: _title(slug),
        description: parts.length > 1
            ? parts.sublist(0, parts.length - 1).join(' / ')
            : '',
      ));
    }
    found.sort((a, b) => a.path.compareTo(b.path));
    return found.take(80).toList();
  }

  Future<Skill> fetchSkill(DiscoveredSkill discovered) async {
    final rawPath =
        '/${discovered.repository.owner}/${discovered.repository.name}/'
        '${discovered.repository.branch}/${discovered.path}';
    final uri = Uri.https('raw.githubusercontent.com', rawPath);
    final response = await client.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw IntegrationException(
          'Could not download ${discovered.name} (HTTP ${response.statusCode}).');
    }
    final raw = response.body;
    if (raw.length > 200000) {
      throw IntegrationException('That skill is too large to import.');
    }
    final parsed = ProjectSkillsStore.parse(raw);
    final instructions = parsed.body.trim();
    if (instructions.isEmpty) {
      throw IntegrationException('That SKILL.md is empty.');
    }
    final name =
        parsed.name.trim().isEmpty ? discovered.name : parsed.name.trim();
    return Skill(
      id: 'skill-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      name: name,
      instructions: instructions,
    );
  }

  static String _title(String slug) => slug
      .split(RegExp(r'[-_]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
