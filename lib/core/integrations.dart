import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'file_types.dart';
import 'project_env.dart';
import 'vfs.dart';

class IntegrationException implements Exception {
  IntegrationException(
    this.message, {
    this.logs,
    this.runtime,
    this.deploymentId,
  });
  final String message;

  /// Masked deploy output for the failure card. Never include credentials.
  final String? logs;
  final String? runtime;
  final String? deploymentId;

  @override
  String toString() => message;
}

class IntegrationResult {
  const IntegrationResult({
    required this.message,
    this.url,
    this.runtime,
    this.logs,
    this.deploymentId,
  });
  final String message;
  final String? url;

  /// The runtime that served this deploy, e.g. Cloudflare Pages or Workers.
  final String? runtime;

  /// Real deploy output: Cloudflare build logs for Pages, Wrangler output for
  /// Workers. Never includes credentials.
  final String? logs;
  final String? deploymentId;

  IntegrationResult copyWith({
    String? message,
    String? url,
    String? runtime,
    String? logs,
    String? deploymentId,
  }) =>
      IntegrationResult(
        message: message ?? this.message,
        url: url ?? this.url,
        runtime: runtime ?? this.runtime,
        logs: logs ?? this.logs,
        deploymentId: deploymentId ?? this.deploymentId,
      );
}

class GitHubRepo {
  const GitHubRepo({
    required this.owner,
    required this.name,
    required this.private,
    required this.defaultBranch,
  });

  final String owner;
  final String name;
  final bool private;
  final String defaultBranch;

  String get fullName => '$owner/$name';
}

class VercelProject {
  const VercelProject({required this.id, required this.name});

  final String id;
  final String name;
}

class CloudflarePagesProject {
  const CloudflarePagesProject({
    required this.name,
    required this.productionBranch,
    this.url = '',
  });

  final String name;
  final String productionBranch;
  final String url;
}

class CloudflareWorker {
  const CloudflareWorker({required this.name, this.modifiedOn = ''});

  final String name;
  final String modifiedOn;
}

class GitHubSnapshot {
  const GitHubSnapshot({
    required this.headSha,
    required this.treeSha,
    required this.files,
    required this.hashes,
  });

  final String? headSha;
  final String? treeSha;

  /// Remote text, used for offline diffs and deployments.
  final Map<String, String> files;

  /// Git blob sha for every file in the tree, including binary files.
  final Map<String, String> hashes;
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

  Future<List<GitHubRepo>> repositories() async {
    final repos = <GitHubRepo>[];
    for (var page = 1; page <= 3; page++) {
      final response = await _client
          .get(
            Uri.parse(
                'https://api.github.com/user/repos?per_page=100&page=$page'
                '&sort=updated&affiliation=owner,collaborator,organization_member'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw IntegrationException(
            _error(response, 'Could not list repositories'));
      }
      final body = jsonDecode(response.body);
      if (body is! List) break;
      for (final item in body) {
        if (item is! Map) continue;
        final owner = (item['owner'] as Map?)?['login'] as String? ?? '';
        final name = item['name'] as String? ?? '';
        if (owner.isEmpty || name.isEmpty) continue;
        repos.add(GitHubRepo(
          owner: owner,
          name: name,
          private: item['private'] as bool? ?? false,
          defaultBranch: item['default_branch'] as String? ?? 'main',
        ));
      }
      if (body.length < 100) break;
    }
    repos.sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return repos;
  }

  Future<GitHubSnapshot> snapshot(
    String owner,
    String repo,
    String branch,
  ) async {
    final head = await headSha(owner, repo, branch);
    if (head == null) {
      return const GitHubSnapshot(
        headSha: null,
        treeSha: null,
        files: {},
        hashes: {},
      );
    }
    final treeResponse = await _client
        .get(
          Uri.parse(
              'https://api.github.com/repos/$owner/$repo/git/trees/$head?recursive=1'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    if (treeResponse.statusCode == 404) {
      return GitHubSnapshot(
        headSha: head,
        treeSha: null,
        files: const {},
        hashes: const {},
      );
    }
    if (treeResponse.statusCode != 200) {
      throw IntegrationException(
          _error(treeResponse, 'Could not compare with the repository'));
    }
    final treeBody = jsonDecode(treeResponse.body) as Map<String, dynamic>;
    final tree = treeBody['tree'];
    if (tree is! List) {
      return GitHubSnapshot(
        headSha: head,
        treeSha: treeBody['sha'] as String?,
        files: const {},
        hashes: const {},
      );
    }
    final hashes = <String, String>{};
    final blobs = <Map<String, dynamic>>[];
    for (final item in tree) {
      if (item is! Map || item['type'] != 'blob') continue;
      final path = item['path'] as String? ?? '';
      final sha = item['sha'] as String? ?? '';
      if (path.isEmpty || sha.isEmpty) continue;
      hashes[path] = sha;
      final size = item['size'] as int? ?? 0;
      if (size > 200000 || !classifyFile(path).isText) continue;
      blobs.add(item.cast<String, dynamic>());
    }
    final files = <String, String>{};
    for (var offset = 0; offset < blobs.length; offset += 6) {
      final chunk = blobs.skip(offset).take(6);
      final results = await Future.wait(chunk.map((item) async {
        final response = await _client
            .get(
              Uri.parse(
                  'https://api.github.com/repos/$owner/$repo/git/blobs/${item['sha']}'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          return const MapEntry<String, String?>('', null);
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final encoded = (body['content'] as String? ?? '').replaceAll('\n', '');
        try {
          return MapEntry(
            item['path'] as String? ?? '',
            utf8.decode(base64Decode(encoded)),
          );
        } catch (_) {
          return const MapEntry<String, String?>('', null);
        }
      }));
      for (final entry in results) {
        if (entry.key.isNotEmpty && entry.value != null) {
          files[entry.key] = entry.value!;
        }
      }
    }
    return GitHubSnapshot(
      headSha: head,
      treeSha: treeBody['sha'] as String?,
      files: files,
      hashes: hashes,
    );
  }

  Future<void> createBranch({
    required String owner,
    required String repo,
    required String branch,
    required String from,
  }) async {
    if (branch.trim().isEmpty) {
      throw IntegrationException('Branch name is required.');
    }
    if (branch.trim().contains(' ')) {
      throw IntegrationException('Branch names cannot contain spaces.');
    }
    final sha = await headSha(owner, repo, from);
    if (sha == null) {
      throw IntegrationException('The base branch $from does not exist yet.');
    }
    final response = await _client
        .post(
          Uri.parse('https://api.github.com/repos/$owner/$repo/git/refs'),
          headers: _jsonHeaders,
          body: jsonEncode({'ref': 'refs/heads/${branch.trim()}', 'sha': sha}),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 201) return;
    throw IntegrationException(_error(response, 'Could not create branch'));
  }

  Future<String?> defaultBranch(String owner, String repo) async {
    final response = await _client
        .get(
          Uri.parse('https://api.github.com/repos/$owner/$repo'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw IntegrationException(
          _error(response, 'Could not read the repository'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['default_branch'] as String?;
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
    required Map<String, List<int>> files,
    String? parentSha,
  }) async {
    if (files.isEmpty) {
      throw IntegrationException('Select at least one file to commit.');
    }

    var parent = parentSha ?? await headSha(owner, repo, branch);
    var remaining = files;
    if (parent == null) {
      await ensureRepo(owner, repo);
      // A missing branch is not the same as an empty repository. Git Data API
      // returns 409 for a repository with no commit, but a 404 for a branch
      // that does not exist. Only seed when the repository's default branch
      // also has no commit.
      final defaultName = await defaultBranch(owner, repo) ?? branch;
      if (defaultName != branch) {
        final defaultHead = await headSha(owner, repo, defaultName);
        if (defaultHead != null) {
          throw IntegrationException(
            'Branch $branch does not exist in $owner/$repo. '
            'Create it first or push to $defaultName.',
          );
        }
      }
      // Git Data API returns 409 for a repository with no commit. Seed the
      // repository through the Contents API with the smallest selected file,
      // then build the real commit on top of that seed. This avoids a
      // placeholder README that would otherwise be left behind.
      final seedPath = files.keys
          .reduce((a, b) => files[a]!.length <= files[b]!.length ? a : b);
      final seed = await _initializeRepository(
        owner: owner,
        repo: repo,
        message: message,
        path: seedPath,
        bytes: files[seedPath]!,
      );
      if (files.length == 1) {
        return GitHubCommit(sha: seed.sha, treeSha: seed.treeSha);
      }
      parent = seed.sha;
      remaining = Map<String, List<int>>.from(files)..remove(seedPath);
    }
    final baseTree = await _treeForCommit(owner, repo, parent);

    final paths = remaining.keys.toList();
    final uploaded = await _mapConcurrent<String, String>(
      paths,
      6,
      (path) async {
        final bytes = remaining[path]!;
        if (bytes.length > 100 * 1024 * 1024) {
          throw IntegrationException(
              '$path is larger than GitHub’s 100 MB blob limit.');
        }
        final blob = await _client
            .post(
              Uri.parse('https://api.github.com/repos/$owner/$repo/git/blobs'),
              headers: _jsonHeaders,
              body: jsonEncode({
                'content': base64Encode(bytes),
                'encoding': 'base64',
              }),
            )
            .timeout(const Duration(seconds: 60));
        if (blob.statusCode != 201) {
          throw IntegrationException(_error(blob, 'Could not upload $path'));
        }
        final blobSha =
            (jsonDecode(blob.body) as Map<String, dynamic>)['sha'] as String?;
        if (blobSha == null) {
          throw IntegrationException('GitHub returned no blob for $path.');
        }
        return blobSha;
      },
    );
    final treeEntries = <Map<String, dynamic>>[
      for (var i = 0; i < paths.length; i++)
        {
          'path': paths[i],
          'mode': '100644',
          'type': 'blob',
          'sha': uploaded[i],
        },
    ];

    final tree = await _client
        .post(
          Uri.parse('https://api.github.com/repos/$owner/$repo/git/trees'),
          headers: _jsonHeaders,
          body: jsonEncode({
            if (baseTree != null) 'base_tree': baseTree,
            'tree': treeEntries,
          }),
        )
        .timeout(const Duration(seconds: 60));
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
            'parents': [parent],
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

  Future<GitHubCommit> _initializeRepository({
    required String owner,
    required String repo,
    required String message,
    required String path,
    required List<int> bytes,
  }) async {
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    final response = await _client
        .put(
          Uri.parse(
              'https://api.github.com/repos/$owner/$repo/contents/$encodedPath'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'message': message,
            'content': base64Encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 201) {
      throw IntegrationException(
          _error(response, 'Could not initialize the empty repository'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final commit = body['commit'] as Map<String, dynamic>? ?? const {};
    final sha = commit['sha'] as String?;
    final treeSha = (commit['tree'] as Map?)?['sha'] as String?;
    if (sha == null || treeSha == null) {
      throw IntegrationException(
          'GitHub initialized the repository without returning a commit.');
    }
    return GitHubCommit(sha: sha, treeSha: treeSha);
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

Future<List<T>> _mapConcurrent<A, T>(
  List<A> items,
  int maxActive,
  Future<T> Function(A item) task,
) async {
  final results = List<T?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= items.length) return;
      results[index] = await task(items[index]);
    }
  }

  final workers = math.min(maxActive, items.length);
  await Future.wait(List.generate(workers, (_) => worker()));
  return results.cast<T>();
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

  Future<List<VercelProject>> projects() async {
    final response = await _client
        .get(
          Uri.parse('https://api.vercel.com/v9/projects?limit=100'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw IntegrationException(_error(response, 'Could not list projects'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = body['projects'];
    if (list is! List) return const [];
    return [
      for (final item in list)
        if (item is Map)
          VercelProject(
            id: item['id'] as String? ?? '',
            name: item['name'] as String? ?? '',
          ),
    ]
        .where((project) => project.id.isNotEmpty && project.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<IntegrationResult> deploy({
    required String name,
    String? projectId,
    required List<DeploymentFile> files,
    String environment = 'production',
    void Function(DeployProgress)? onProgress,
  }) async {
    if (token.trim().isEmpty) {
      throw IntegrationException('Add a Vercel account first.');
    }
    if (files.isEmpty) {
      throw IntegrationException('This project has no files to deploy.');
    }
    onProgress?.call(DeployProgress(
      'Uploading',
      detail: '${files.length} files',
    ));
    final account = await login();
    final payload = <String, dynamic>{
      'name': name,
      if (projectId != null && projectId.isNotEmpty) 'project': projectId,
      'target': environment == 'preview' ? 'preview' : 'production',
      'files': [
        for (final file in files)
          {
            'file': file.path,
            'data': file.isText ? file.text : base64Encode(file.bytes),
            'encoding': file.isText ? 'utf-8' : 'base64',
          },
      ],
      'projectSettings': {'framework': null},
    };
    final response = await _client
        .post(
          Uri.parse('https://api.vercel.com/v13/deployments'),
          headers: _headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 120));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw IntegrationException(_error(response, 'Deployment failed'));
    }
    onProgress?.call(const DeployProgress(
      'Building',
      detail: 'Vercel is compiling the deployment',
    ));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      return IntegrationResult(
          message: 'Deployment queued for @$account · ${files.length} files.');
    }
    return IntegrationResult(
      message: 'Deployed ${files.length} files for @$account to Vercel '
          '${environment == 'preview' ? 'preview' : 'production'}.',
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

/// One step of a deployment, surfaced to the deploy sheet so a long upload
/// shows what is happening instead of an indefinite spinner.
class DeployProgress {
  const DeployProgress(this.stage, {this.detail = '', this.value});

  final String stage;
  final String detail;
  final double? value;
}

/// Cloudflare Pages Direct Upload. Assets are uploaded to the Pages asset
/// store with a short-lived JWT, then a deployment manifest points at them.
class CloudflarePagesClient {
  CloudflarePagesClient(
    this.token, {
    this.accountId = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String token;

  /// The account that owns the Pages projects. Cloudflare requires this
  /// alongside the API token; when omitted, older accounts fall back to the
  /// first account returned by the token.
  final String accountId;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<(String, String)> _account() async {
    final configured = accountId.trim();
    if (configured.isNotEmpty) {
      return (configured, 'Cloudflare');
    }
    final response = await _client
        .get(Uri.parse('https://api.cloudflare.com/client/v4/accounts'),
            headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw IntegrationException(
          _error(response, 'Cloudflare rejected the token'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final result = body['result'];
    if (body['success'] != true || result is! List || result.isEmpty) {
      throw IntegrationException(
          'No Cloudflare account is available for this token.');
    }
    final first = result.first as Map;
    final id = first['id'] as String? ?? '';
    final name = first['name'] as String? ?? 'Cloudflare';
    if (id.isEmpty) {
      throw IntegrationException('Cloudflare returned no account id.');
    }
    return (id, name);
  }

  Future<String> login() async => (await _account()).$2;

  /// Resolves the account id when the saved account did not record one.
  Future<String> accountIdentifier() async => (await _account()).$1;

  Future<List<CloudflarePagesProject>> projects() async {
    final (accountId, _) = await _account();
    final projects = <String, CloudflarePagesProject>{};
    final base = 'https://api.cloudflare.com/client/v4/accounts/'
        '$accountId/pages/projects';
    var page = 1;
    var totalPages = 1;
    var paginated = true;
    while (page <= totalPages && page <= 20) {
      final response = await _client
          .get(
            Uri.parse(paginated ? '$base?page=$page' : base),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 45));
      // Some account setups reject list options on Pages with a 400. The plain
      // endpoint still returns the projects, so fall back instead of showing an
      // empty list.
      if (response.statusCode == 400 && paginated) {
        paginated = false;
        page = 1;
        continue;
      }
      if (response.statusCode != 200) {
        throw IntegrationException(
            _error(response, 'Could not list Pages projects'));
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] == false) {
        if (paginated) {
          paginated = false;
          page = 1;
          continue;
        }
        throw IntegrationException(
            _error(response, 'Could not list Pages projects'));
      }
      final list = body['result'];
      if (list is! List || list.isEmpty) break;
      for (final item in list) {
        if (item is! Map) continue;
        final name = item['name'] as String? ?? '';
        if (name.isEmpty) continue;
        projects[name] = CloudflarePagesProject(
          name: name,
          productionBranch: item['production_branch'] as String? ?? 'main',
          url:
              item['subdomain'] is String ? 'https://${item['subdomain']}' : '',
        );
      }
      if (!paginated) break;
      final info = body['result_info'];
      totalPages =
          info is Map ? (info['total_pages'] as num?)?.toInt() ?? 1 : 1;
      page++;
    }
    return projects.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Existing Worker scripts in the account, so a project can deploy to one
  /// that already has routes, bindings and Variables instead of creating a
  /// second script from the wrangler config name.
  Future<List<CloudflareWorker>> workers() async {
    final (accountId, _) = await _account();
    final response = await _client
        .get(
          Uri.parse('https://api.cloudflare.com/client/v4/accounts/'
              '$accountId/workers/scripts?per_page=100'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw IntegrationException(
          _error(response, 'Could not list Workers scripts'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = body['result'];
    if (body['success'] != true || list is! List) {
      throw IntegrationException(
          _error(response, 'Could not list Workers scripts'));
    }
    final workers = <String, CloudflareWorker>{};
    for (final item in list) {
      if (item is! Map) continue;
      final name =
          (item['id'] as String? ?? item['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      workers[name] = CloudflareWorker(
        name: name,
        modifiedOn: item['modified_on'] as String? ?? '',
      );
    }
    return workers.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<CloudflarePagesProject> createProject(
    String name, {
    String branch = 'main',
  }) async {
    final (accountId, _) = await _account();
    final response = await _client
        .post(
          Uri.parse('https://api.cloudflare.com/client/v4/accounts/'
              '$accountId/pages/projects'),
          headers: _headers,
          body: jsonEncode({
            'name': name,
            'production_branch': branch,
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IntegrationException(
          _error(response, 'Could not create the Pages project'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final result = body['result'] as Map<String, dynamic>?;
    final subdomain = result?['subdomain'] as String? ?? '';
    return CloudflarePagesProject(
      name: result?['name'] as String? ?? name,
      productionBranch: result?['production_branch'] as String? ?? branch,
      url: subdomain.isEmpty ? '' : 'https://$subdomain',
    );
  }

  Future<IntegrationResult> deploy({
    required String project,
    String projectUrl = '',
    required List<DeploymentFile> files,
    String environment = 'production',
    String branch = 'main',
    void Function(DeployProgress)? onProgress,
  }) async {
    if (files.isEmpty) {
      throw IntegrationException('This project has no files to deploy.');
    }
    if (files.length > 20000) {
      throw IntegrationException(
          'Pages accepts at most 20,000 files. This project has '
          '${files.length}.');
    }
    for (final file in files) {
      if (file.bytes.length > 24 * 1024 * 1024) {
        throw IntegrationException(
            '${file.path} is ${(file.bytes.length / (1024 * 1024)).toStringAsFixed(1)} '
            'MB. Pages accepts files up to 24 MB.');
      }
    }
    final (accountId, accountName) = await _account();
    final tokenResponse = await _client
        .get(
          Uri.parse('https://api.cloudflare.com/client/v4/accounts/'
              '$accountId/pages/projects/$project/upload-token'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));
    if (tokenResponse.statusCode != 200) {
      throw IntegrationException(
          _error(tokenResponse, 'Could not get a Pages upload token'));
    }
    final tokenBody = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    final jwt = (tokenBody['result'] as Map?)?['jwt'] as String? ?? '';
    if (jwt.isEmpty) {
      throw IntegrationException('Cloudflare returned no upload token.');
    }

    // Pages only serves an asset at a request path when the manifest key is an
    // absolute path. Keys without the leading slash upload cleanly and then
    // every URL 404s, which is what made new deployments look empty.
    final hashes = <String, String>{};
    for (final file in files) {
      hashes['/${file.path}'] = digestForPagesBytes(file.bytes);
    }
    final uploads = <Map<String, dynamic>>[
      for (final file in files)
        {
          'base64': true,
          'key': hashes['/${file.path}'],
          'value': base64Encode(file.bytes),
          'metadata': {'contentType': _contentType(file.path, file.mime)},
        },
    ];
    // A Node build can contain thousands of files and hundreds of megabytes.
    // Fixed 50-file batches produced request bodies large enough for Cloudflare
    // to answer with a 500. Batch by encoded size and retry a transient 429/5xx.
    var chunk = <Map<String, dynamic>>[];
    var chunkBytes = 0;
    var sent = 0;
    Future<void> sendChunk() async {
      if (chunk.isEmpty) return;
      final payload = chunk;
      chunk = <Map<String, dynamic>>[];
      chunkBytes = 0;
      http.Response? response;
      var failure = 'Could not upload Pages assets.';
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          response = await _client
              .post(
                Uri.parse(
                    'https://api.cloudflare.com/client/v4/pages/assets/upload'),
                headers: {
                  'Authorization': 'Bearer $jwt',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 90));
          if (response.statusCode != 429 && response.statusCode < 500) break;
          failure = _error(response, 'Could not upload Pages assets');
          response = null;
        } catch (error) {
          failure = '$error';
          response = null;
        }
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
        }
      }
      final result = response;
      if (result == null) throw IntegrationException(failure);
      if (result.statusCode < 200 || result.statusCode >= 300) {
        throw IntegrationException(
            _error(result, 'Could not upload Pages assets'));
      }
      sent += payload.length;
      onProgress?.call(DeployProgress(
        'Uploading',
        detail: '$sent of ${uploads.length} files',
        value: uploads.isEmpty ? null : sent / uploads.length,
      ));
    }

    for (final upload in uploads) {
      final size = (upload['value'] as String).length;
      if (chunk.isNotEmpty && chunkBytes + size > 3 * 1024 * 1024) {
        await sendChunk();
      }
      chunk.add(upload);
      chunkBytes += size;
    }
    await sendChunk();

    onProgress?.call(const DeployProgress(
      'Deploying',
      detail: 'Publishing the Pages deployment',
    ));
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudflare.com/client/v4/accounts/'
          '$accountId/pages/projects/$project/deployments'),
    )..headers['Authorization'] = 'Bearer $token';
    request.fields.addAll({
      'manifest': jsonEncode(hashes),
      'branch': branch,
      'environment': environment == 'preview' ? 'preview' : 'production',
      'commit_message': 'Deploy ${files.length} files from Praxis',
      'commit_dirty': 'true',
    });
    final response = await http.Response.fromStream(
      await request.send().timeout(const Duration(seconds: 90)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IntegrationException(_error(response, 'Deployment failed'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final result = body['result'] as Map<String, dynamic>?;
    final deploymentId = result?['id'] as String? ?? '';
    final stage = result?['latest_stage'];
    if (stage is Map && stage['status'] == 'failure') {
      // Do not attach raw logs here. The app fetches failed-build output
      // through the project-aware masked log path, which knows the secrets and
      // applies the cutoff only after masking.
      throw IntegrationException(
        'Cloudflare Pages deployment failed. Open the logs for the build '
        'error.',
        runtime: 'Cloudflare Pages',
        deploymentId: deploymentId,
      );
    }
    final deploymentUrl = result?['url'] as String? ?? '';
    final aliases = result?['aliases'];
    final firstAlias =
        aliases is List && aliases.isNotEmpty ? aliases.first.toString() : '';
    final known = projectUrl.trim();
    // Cloudflare assigns a unique subdomain when the plain project name is
    // taken (portfolio becomes portfolio-36k.pages.dev). Never invent
    // <name>.pages.dev: prefer the project the API returned, then the actual
    // deployment URL, then an alias.
    final productionUrl = known.isNotEmpty
        ? known
        : (deploymentUrl.isNotEmpty
            ? deploymentUrl
            : (firstAlias.startsWith('http')
                ? firstAlias
                : 'https://$project.pages.dev'));
    final previewUrl = deploymentUrl.isNotEmpty
        ? deploymentUrl
        : (firstAlias.startsWith('http') ? firstAlias : productionUrl);
    final url = environment == 'production' ? productionUrl : previewUrl;
    onProgress?.call(DeployProgress('Live', detail: url));
    return IntegrationResult(
      message: 'Deployed ${files.length} files to $accountName · '
          '$project ${environment == 'preview' ? 'preview' : 'production'}.',
      url: url,
      runtime: 'Cloudflare Pages',
      deploymentId: deploymentId,
    );
  }

  /// Fetch the actual build log for a Pages deployment. Cloudflare wraps the
  /// entries in `result.data`; older responses put `data` at the top level.
  Future<String> deploymentLogs({
    required String project,
    required String deploymentId,
    required Iterable<ProjectEnvEntry> secrets,
  }) async {
    final (accountId, _) = await _account();
    final response = await _client
        .get(
          Uri.parse(
            'https://api.cloudflare.com/client/v4/accounts/$accountId/pages/'
            'projects/${Uri.encodeComponent(project)}/deployments/'
            '${Uri.encodeComponent(deploymentId)}/history/logs',
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw IntegrationException(
          _error(response, 'Could not fetch Pages deployment logs'));
    }
    final decoded = jsonDecode(response.body);
    final root = decoded is Map && decoded['result'] is Map
        ? decoded['result'] as Map
        : decoded;
    final data = root is Map ? root['data'] : null;
    if (data is! List) return '';
    final lines = <String>[];
    for (final item in data) {
      if (item is! Map) continue;
      final line = '${item['line'] ?? ''}'.trimRight();
      if (line.isEmpty) continue;
      final ts = '${item['ts'] ?? ''}'.trim();
      lines.add(ts.isEmpty ? line : '$ts  $line');
    }
    // Mask first, then truncate. The returned log is safe to pass to the
    // agent, the UI, an exception, or the persisted deploy record.
    return maskSecretLog(lines.join('\n'), secrets);
  }

  Future<String> latestDeploymentId(String project) async {
    final (accountId, _) = await _account();
    final response = await _client
        .get(
          Uri.parse(
            'https://api.cloudflare.com/client/v4/accounts/$accountId/pages/'
            'projects/${Uri.encodeComponent(project)}/deployments?per_page=1',
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw IntegrationException(
          _error(response, 'Could not find the latest Pages deployment'));
    }
    final decoded = jsonDecode(response.body);
    final result = decoded is Map ? decoded['result'] : null;
    if (result is! List || result.isEmpty || result.first is! Map) return '';
    return (result.first as Map)['id'] as String? ?? '';
  }

  String _error(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final errors = body['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        final message = (errors.first as Map)['message'];
        if (message is String && message.isNotEmpty) {
          return '$fallback (${response.statusCode}): $message';
        }
      }
    } catch (_) {}
    return '$fallback (HTTP ${response.statusCode}).';
  }

  static String _contentType(String path, String fallback) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html')) return 'text/html; charset=utf-8';
    if (lower.endsWith('.css')) return 'text/css; charset=utf-8';
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
      return 'application/javascript; charset=utf-8';
    }
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    return fallback.trim().isEmpty ? 'application/octet-stream' : fallback;
  }
}

String digestForPages(String content) =>
    sha256.convert(utf8.encode(content)).toString().substring(0, 32);

String digestForPagesBytes(List<int> bytes) =>
    sha256.convert(bytes).toString().substring(0, 32);
