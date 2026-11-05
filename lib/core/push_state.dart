import 'dart:convert';
import 'dart:io';

import 'vfs.dart';

enum RepoChangeStatus { modified, added }

extension RepoChangeStatusX on RepoChangeStatus {
  /// VS Code-style single letter: M for an existing file, A for a new one.
  /// Praxis uses N for "new" in the UI because that is the requested label.
  String get letter => this == RepoChangeStatus.modified ? 'M' : 'N';
  String get label => this == RepoChangeStatus.modified ? 'Modified' : 'New';
}

class RepoChange {
  const RepoChange({
    required this.path,
    required this.status,
    required this.before,
    required this.after,
    required this.added,
    required this.removed,
  });

  final String path;
  final RepoChangeStatus status;
  final String before;
  final String after;
  final int added;
  final int removed;
}

class PendingCommit {
  const PendingCommit({
    required this.sha,
    required this.message,
    required this.at,
    required this.owner,
    required this.repo,
    required this.branch,
    this.files = const {},
  });

  final String sha;
  final String message;
  final DateTime at;
  final String owner;
  final String repo;
  final String branch;

  /// Contents at commit time, used to advance the baseline only after a push.
  final Map<String, String> files;

  bool matches(String owner, String repo, String branch) =>
      this.owner == owner && this.repo == repo && this.branch == branch;

  Map<String, dynamic> toJson() => {
        'sha': sha,
        'message': message,
        'at': at.toIso8601String(),
        'owner': owner,
        'repo': repo,
        'branch': branch,
        'files': files,
      };

  static PendingCommit? fromJson(Map<String, dynamic> json) {
    final sha = json['sha'] as String? ?? '';
    if (sha.isEmpty) return null;
    return PendingCommit(
      sha: sha,
      message: json['message'] as String? ?? 'Commit from Praxis',
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      owner: json['owner'] as String? ?? '',
      repo: json['repo'] as String? ?? '',
      branch: json['branch'] as String? ?? 'main',
      files: (json['files'] as Map?)?.map(
            (key, value) => MapEntry('$key', '$value'),
          ) ??
          const {},
    );
  }
}

/// Persisted inside `.praxis/push.json` in the project. Baselines hold the
/// exact text that was last pushed so a diff works offline. Pending commits are
/// local commit objects whose ref has not been updated yet.
class PushState {
  const PushState({
    this.owner = '',
    this.repo = '',
    this.branch = 'main',
    this.baseline = const {},
    this.pending = const [],
  });

  final String owner;
  final String repo;
  final String branch;
  final Map<String, String> baseline;
  final List<PendingCommit> pending;

  String get slug => owner.isEmpty || repo.isEmpty ? '' : '$owner/$repo';

  int pendingFor(String owner, String repo, String branch) =>
      pending.where((commit) => commit.matches(owner, repo, branch)).length;

  PendingCommit? lastPendingFor(String owner, String repo, String branch) {
    for (final commit in pending.reversed) {
      if (commit.matches(owner, repo, branch)) return commit;
    }
    return null;
  }

  PushState copyWith({
    String? owner,
    String? repo,
    String? branch,
    Map<String, String>? baseline,
    List<PendingCommit>? pending,
  }) =>
      PushState(
        owner: owner ?? this.owner,
        repo: repo ?? this.repo,
        branch: branch ?? this.branch,
        baseline: baseline ?? this.baseline,
        pending: pending ?? this.pending,
      );

  PushState withPending(PendingCommit commit) =>
      copyWith(pending: [...pending, commit]);

  PushState withoutPending(Iterable<String> shas) {
    final drop = shas.toSet();
    return copyWith(
      pending: pending.where((commit) => !drop.contains(commit.sha)).toList(),
    );
  }

  PushState withBaseline(Map<String, String> files) {
    final merged = Map<String, String>.from(baseline)..addAll(files);
    return copyWith(baseline: merged);
  }

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'repo': repo,
        'branch': branch,
        'baseline': baseline,
        'pending': pending.map((commit) => commit.toJson()).toList(),
      };

  static PushState fromJson(Map<String, dynamic> json) => PushState(
        owner: json['owner'] as String? ?? '',
        repo: json['repo'] as String? ?? '',
        branch: json['branch'] as String? ?? 'main',
        baseline: (json['baseline'] as Map?)?.map(
              (key, value) => MapEntry('$key', '$value'),
            ) ??
            const {},
        pending: [
          for (final item in (json['pending'] as List? ?? const []))
            if (item is Map)
              if (PendingCommit.fromJson(item.cast<String, dynamic>())
                  case final commit?)
                commit,
        ],
      );
}

class PushStore {
  const PushStore._();

  static File fileFor(ProjectFs fs) => File('${fs.rootPath}/.praxis/push.json');

  static Future<PushState> load(ProjectFs fs) async {
    final file = fileFor(fs);
    if (!await file.exists()) return const PushState();
    try {
      final raw = await file.readAsString();
      return PushState.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return const PushState();
    }
  }

  static Future<void> save(ProjectFs fs, PushState state) async {
    final file = fileFor(fs);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(state.toJson()));
  }
}
