import 'dart:convert';

import 'package:http/http.dart' as http;

class IntegrationException implements Exception {
  IntegrationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class IntegrationResult {
  const IntegrationResult({required this.message, this.url});
  final String message;
  final String? url;
}

class GitHubCommit {
  const GitHubCommit({
    required this.sha,
    required this.treeSha,
    this.parentSha,
  });

  final String sha;
  final String treeSha;
  final String? parentSha;
}

/// GitHub REST client. Commits are real git commits: blobs, a tree built on
/// the branch's previous tree, a commit object, then a ref update on push.
class GitHubClient {
  GitHubClient(this.token, {http.Client? client})
      : _client = client ?? http.Client();

  final String token;
  final http.Client _client;
  String? _loginCache;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Praxis',
      };

  Map<String, String> get _jsonHeaders => {
        ..._headers,
        'Content-Type': 'application/json',
      };

  Future<String> login() async {
    if (_loginCache != null) return _loginCache!;
    final response = await _client
        .get(Uri.parse('https://api.github.com/user'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw IntegrationException(_error(response, 'GitHub rejected the token'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final login = body['login'] as String? ?? '';
    if (login.isEmpty) {
      throw IntegrationException('GitHub did not return an account name.');
    }
    _loginCache = login;
    return login;
  }

  Future<List<String>> branches(String owner, String repo) async {
    final response = await _client
        .get(
          Uri.parse(
              'https://api.github.com/repos/$owner/$repo/branches?per_page=100'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) return const [];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IntegrationException(_error(response, 'Could not list branches'));
    }
    final body = jsonDecode(response.body);
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map && item['name'] is String) item['name'] as String,
    ];
  }

  Future<void> ensureRepo(
    String owner,
    String repo, {
    bool private = true,
  }) async {
    if (token.trim().isEmpty) {
      throw IntegrationException('Add a GitHub account first.');
    }
    if (owner.trim().isEmpty || repo.trim().isEmpty) {
      throw IntegrationException('Repository owner and name are required.');
    }
    final uri = Uri.parse('https://api.github.com/repos/$owner/$repo');
    final existing = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (existing.statusCode == 200) return;
    if (existing.statusCode != 404) {
      throw IntegrationException(
          _error(existing, 'Could not read the repository'));
    }
    final currentLogin = await login();
    if (owner != currentLogin) {
      throw IntegrationException(
          'Repository $owner/$repo does not exist. Praxis can create repos only under your own account ($currentLogin).');
    }
    final created = await _client
        .post(
          Uri.parse('https://api.github.com/user/repos'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'name': repo,
            'private': private,
            'auto_init': false,
            'description': 'A Praxis project',
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (created.statusCode != 201) {
      throw IntegrationException(_error(created, 'Could not create the repo'));
    }
  }

  Future<String?> headSha(String owner, String repo, String branch) async {
    final response = await _client
        .get(
          Uri.parse(
              'https://api.github.com/repos/$owner/$repo/git/refs/heads/$branch'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 404 || response.statusCode == 409) return null;
    if (response.statusCode != 200) {
      throw IntegrationException(
          _error(response, 'Could not read branch $branch'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['object'] is Map) {
      return (body['object'] as Map)['sha'] as String?;
    }
    return body['sha'] as String?;
  }

  Future<String?> _treeForCommit(String owner, String repo, String sha) async {
    final response = await _client
        .get(
          Uri.parse(
              'https://api.github.com/repos/$owner/$repo/git/commits/$sha'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw IntegrationException(
          _error(response, 'Could not read the base commit'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['tree'] as Map?)?['sha'] as String?;
  }

  /// Creates a commit but does not update the branch. [parentSha] can be the
  /// previous local pending commit, which lets the user commit several times
  /// before pushing.
  Future<GitHubCommit> createCommit({
    required String owner,
    required String repo,
    required String branch,
    required String message,
    required Map<String, String> files,
    String? parentSha,
  }) async {
    if (files.isEmpty) {
      throw IntegrationException('Select at least one file to commit.');
    }
    await ensureRepo(owner, repo);
    final parent = parentSha ?? await headSha(owner, repo, branch);
    final baseTree =
        parent == null ? null : await _treeForCommit(owner, repo, parent);

    final treeEntries = <Map<String, dynamic>>[];
    for (final entry in files.entries) {
      final blob = await _client
          .post(
            Uri.parse('https://api.github.com/repos/$owner/$repo/git/blobs'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'content': base64Encode(utf8.encode(entry.value)),
              'encoding': 'base64',
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (blob.statusCode != 201) {
        throw IntegrationException(
            _error(blob, 'Could not upload ${entry.key}'));
      }
      final blobSha =
          (jsonDecode(blob.body) as Map<String, dynamic>)['sha'] as String?;
      if (blobSha == null) {
        throw IntegrationException('GitHub returned no blob for ${entry.key}.');
      }
      treeEntries.add({
        'path': entry.key,
        'mode': '100644',
        'type': 'blob',
        'sha': blobSha,
      });
    }

    final tree = await _client
        .post(
          Uri.parse('https://api.github.com/repos/$owner/$repo/git/trees'),
          headers: _jsonHeaders,
          body: jsonEncode({
            if (baseTree != null) 'base_tree': baseTree,
            'tree': treeEntries,
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (tree.statusCode != 201) {
      throw IntegrationException(
          _error(tree, 'Could not build the commit tree'));
    }
    final treeSha =
        (jsonDecode(tree.body) as Map<String, dynamic>)['sha'] as String?;
    if (treeSha == null) {
      throw IntegrationException('GitHub returned no tree for this commit.');
    }

    final commit = await _client
        .post(
          Uri.parse('https://api.github.com/repos/$owner/$repo/git/commits'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'message': message,
            'tree': treeSha,
            'parents': parent == null ? <String>[] : [parent],
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (commit.statusCode != 201) {
      throw IntegrationException(_error(commit, 'Could not create the commit'));
    }
    final sha =
        (jsonDecode(commit.body) as Map<String, dynamic>)['sha'] as String?;
    if (sha == null) {
      throw IntegrationException('GitHub returned no commit SHA.');
    }
    return GitHubCommit(sha: sha, treeSha: treeSha, parentSha: parent);
  }

  Future<void> pushRef({
    required String owner,
    required String repo,
    required String branch,
    required String sha,
  }) async {
    final uri = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/git/refs/heads/$branch');
    final patched = await _client
        .patch(
          uri,
          headers: _jsonHeaders,
          body: jsonEncode({'sha': sha, 'force': false}),
        )
        .timeout(const Duration(seconds: 30));
    if (patched.statusCode == 200) return;
    if (patched.statusCode == 404 || patched.statusCode == 422) {
      final created = await _client
          .post(
            Uri.parse('https://api.github.com/repos/$owner/$repo/git/refs'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'ref': 'refs/heads/$branch',
              'sha': sha,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (created.statusCode == 201) return;
      throw IntegrationException(
          _error(created, 'Could not create branch $branch'));
    }
    throw IntegrationException(
        _error(patched, 'Could not push branch $branch'));
  }

  String _error(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final message = body['message'] as String?;
      if (message != null && message.isNotEmpty) {
        return '$fallback (${response.statusCode}): $message';
      }
    } catch (_) {
      // ignore
    }
    return '$fallback (HTTP ${response.statusCode}).';
  }
}

/// Vercel REST client: verifies the token and deploys the project's text files
/// as a static deployment.
class VercelClient {
  VercelClient(this.token, {http.Client? client})
      : _client = client ?? http.Client();

  final String token;
  final http.Client _client;
  String? _loginCache;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<String> login() async {
    if (_loginCache != null) return _loginCache!;
    final response = await _client
        .get(Uri.parse('https://api.vercel.com/v2/user'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw IntegrationException(_error(response, 'Vercel rejected the token'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = body['user'] as Map<String, dynamic>? ?? const {};
    final name =
        user['username'] as String? ?? user['email'] as String? ?? 'account';
    _loginCache = name;
    return name;
  }

  Future<IntegrationResult> deploy({
    required String name,
    required Map<String, String> files,
  }) async {
    if (token.trim().isEmpty) {
      throw IntegrationException('Add a Vercel account first.');
    }
    if (files.isEmpty) {
      throw IntegrationException('This project has no text files to deploy.');
    }
    final account = await login();
    final response = await _client
        .post(
          Uri.parse('https://api.vercel.com/v13/deployments'),
          headers: _headers,
          body: jsonEncode({
            'name': name,
            'target': 'production',
            'files': [
              for (final entry in files.entries)
                {
                  'file': entry.key,
                  'data': entry.value,
                  'encoding': 'utf-8',
                },
            ],
            'projectSettings': {'framework': null},
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw IntegrationException(_error(response, 'Deployment failed'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      return IntegrationResult(
          message: 'Deployment queued for @$account · ${files.length} files.');
    }
    return IntegrationResult(
      message:
          'Deployed ${files.length} files for @$account to Vercel production.',
      url: 'https://$url',
    );
  }

  String _error(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'];
      if (error is Map && error['message'] is String) {
        return '$fallback (${response.statusCode}): ${error['message']}';
      }
    } catch (_) {
      // ignore
    }
    return '$fallback (HTTP ${response.statusCode}).';
  }
}
