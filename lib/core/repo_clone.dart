import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

class RepoRef {
  const RepoRef({required this.owner, required this.name});

  final String owner;
  final String name;

  String get slug => '$owner/$name';

  static RepoRef? parse(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    value = value.replaceFirst(RegExp(r'^https?://'), '');
    value = value.replaceFirst(RegExp(r'^www\.'), '');
    if (value.startsWith('github.com/')) {
      value = value.substring('github.com/'.length);
    } else if (value.contains('/') && !value.startsWith('github.com')) {
      // Accept owner/repo as the short form; reject other hosts.
      if (RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+').hasMatch(value) &&
          !value.contains(':')) {
        // keep going
      } else {
        return null;
      }
    }
    value = value.split('?').first.split('#').first;
    final parts = value.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return null;
    final owner = parts[0];
    var name = parts[1];
    if (name.endsWith('.git')) name = name.substring(0, name.length - 4);
    if (owner.isEmpty || name.isEmpty) return null;
    return RepoRef(owner: owner, name: name);
  }
}

class RepoCloneException implements Exception {
  RepoCloneException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ClonedRepo {
  const ClonedRepo({required this.files, required this.branch});
  final Map<String, List<int>> files;
  final String branch;
}

class RepoCloneService {
  RepoCloneService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers(String token) => {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Praxis',
        if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
      };

  Future<List<String>> branches(RepoRef repo, {String token = ''}) async {
    final uri = Uri.parse(
        'https://api.github.com/repos/${repo.owner}/${repo.name}/branches?per_page=100');
    final response = await _client.get(uri, headers: _headers(token)).timeout(
          const Duration(seconds: 30),
        );
    if (response.statusCode == 404) {
      throw RepoCloneException('Repository ${repo.slug} was not found.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RepoCloneException(
          'Could not list branches (HTTP ${response.statusCode}). Check the token for private repos.');
    }
    final body = jsonDecode(response.body);
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map && item['name'] is String) item['name'] as String,
    ];
  }

  Future<ClonedRepo> clone({
    required RepoRef repo,
    required String branch,
    String token = '',
  }) async {
    if (branch.trim().isEmpty) {
      throw RepoCloneException('Choose a branch to clone.');
    }
    final uri = Uri.parse(
        'https://codeload.github.com/${repo.owner}/${repo.name}/zip/refs/heads/${Uri.encodeComponent(branch.trim())}');
    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'User-Agent': 'Praxis',
        'Accept': 'application/zip',
        if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
      }).timeout(const Duration(seconds: 90));
    } catch (error) {
      throw RepoCloneException('Could not download the repository: $error');
    }
    if (response.statusCode == 404) {
      throw RepoCloneException(
          'Branch "${branch.trim()}" was not found in ${repo.slug}.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RepoCloneException(
          'GitHub returned HTTP ${response.statusCode} while downloading the archive.');
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(response.bodyBytes);
    } catch (_) {
      throw RepoCloneException('GitHub sent an archive Praxis could not read.');
    }

    final files = <String, List<int>>{};
    var prefix = '';
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final path = file.name.replaceAll('\\', '/');
      if (path.startsWith('__MACOSX/')) continue;
      final slash = path.indexOf('/');
      if (slash <= 0) continue;
      if (prefix.isEmpty) prefix = path.substring(0, slash + 1);
      final relative = path.startsWith(prefix)
          ? path.substring(prefix.length)
          : path.substring(slash + 1);
      if (relative.isEmpty ||
          relative == '.git' ||
          relative.startsWith('.git/')) {
        continue;
      }
      files[relative] = Uint8List.fromList(file.content as List<int>);
    }
    if (files.isEmpty) {
      throw RepoCloneException('The branch is empty.');
    }
    return ClonedRepo(files: files, branch: branch.trim());
  }
}
