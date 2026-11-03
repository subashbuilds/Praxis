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

/// GitHub REST client: verifies the token, creates the repo if needed and
/// commits every text file through the contents API.
class GitHubClient {
  GitHubClient(this.token, {http.Client? client})
      : _client = client ?? http.Client();

  final String token;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'DevNest',
      };

  Future<String> login() async {
    final response = await _client
        .get(Uri.parse('https://api.github.com/user'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw IntegrationException(
          _githubError(response, 'GitHub rejected the token'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['login'] as String? ?? '';
  }

  Future<IntegrationResult> push({
    required String repoName,
    required bool private,
    required Map<String, String> files,
  }) async {
    if (token.trim().isEmpty) {
      throw IntegrationException('Add a GitHub token first.');
    }
    if (files.isEmpty) {
      throw IntegrationException('This project has no text files to push.');
    }
    final owner = await login();
    if (owner.isEmpty) {
      throw IntegrationException('Could not read the GitHub account.');
    }

    final repoUri = Uri.parse('https://api.github.com/repos/$owner/$repoName');
    final existing = await _client
        .get(repoUri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (existing.statusCode == 404) {
      final created = await _client
          .post(
            Uri.parse('https://api.github.com/user/repos'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': repoName,
              'private': private,
              'auto_init': false,
              'description': 'Created from DevNest on Android',
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (created.statusCode != 201) {
        throw IntegrationException(
            _githubError(created, 'Could not create the repo'));
      }
    } else if (existing.statusCode >= 400) {
      throw IntegrationException(
          _githubError(existing, 'Could not read the repo'));
    }

    var pushed = 0;
    for (final entry in files.entries) {
      final contentUri = Uri.parse(
          'https://api.github.com/repos/$owner/$repoName/contents/${entry.key}');
      var sha = '';
      final current = await _client
          .get(contentUri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (current.statusCode == 200) {
        final body = jsonDecode(current.body) as Map<String, dynamic>;
        sha = body['sha'] as String? ?? '';
      }
      final put = await _client
          .put(
            contentUri,
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': 'Update ${entry.key} from DevNest',
              'content': base64Encode(utf8.encode(entry.value)),
              if (sha.isNotEmpty) 'sha': sha,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (put.statusCode != 200 && put.statusCode != 201) {
        throw IntegrationException(
          _githubError(put, 'Failed to push ${entry.key}'),
        );
      }
      pushed++;
    }

    final url = 'https://github.com/$owner/$repoName';
    return IntegrationResult(
      message:
          'Pushed $pushed file${pushed == 1 ? '' : 's'} to $owner/$repoName.',
      url: url,
    );
  }

  String _githubError(http.Response response, String fallback) {
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

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<String> login() async {
    final response = await _client
        .get(Uri.parse('https://api.vercel.com/v2/user'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw IntegrationException(
          _vercelError(response, 'Vercel rejected the token'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = body['user'] as Map<String, dynamic>? ?? const {};
    return user['username'] as String? ?? user['email'] as String? ?? 'account';
  }

  Future<IntegrationResult> deploy({
    required String name,
    required Map<String, String> files,
  }) async {
    if (token.trim().isEmpty) {
      throw IntegrationException('Add a Vercel token first.');
    }
    if (files.isEmpty) {
      throw IntegrationException('This project has no text files to deploy.');
    }
    await login();
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
      throw IntegrationException(_vercelError(response, 'Deployment failed'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      return const IntegrationResult(message: 'Deployment queued.');
    }
    return IntegrationResult(
      message: 'Deployed ${files.length} files to Vercel.',
      url: 'https://$url',
    );
  }

  String _vercelError(http.Response response, String fallback) {
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
