import 'dart:convert';
import 'dart:io';

import 'vfs.dart';

enum RepoChangeStatus { modified, added, deleted }

extension RepoChangeStatusX on RepoChangeStatus {
  /// VS Code-style single letter: M for an existing file, N for a new one,
  /// D for a file removed from this device.
  String get letter => switch (this) {
        RepoChangeStatus.modified => 'M',
        RepoChangeStatus.added => 'N',
        RepoChangeStatus.deleted => 'D',
      };
  String get label => switch (this) {
        RepoChangeStatus.modified => 'Modified',
        RepoChangeStatus.added => 'New',
        RepoChangeStatus.deleted => 'Deleted',
      };
}

class RepoChange {
  const RepoChange({
    required this.path,
    required this.status,
    required this.before,
    required this.after,
    required this.added,
    required this.removed,
    this.isBinary = false,
    this.size = 0,
  });

  final String path;
  final RepoChangeStatus status;
  final String before;
  final String after;
  final int added;
  final int removed;

  /// Binary files have no line diff, but they still participate in commits.
  final bool isBinary;
  final int size;
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
    this.hashes = const {},
    this.deleted = const [],
  });

  final String sha;
  final String message;
  final DateTime at;
  final String owner;
  final String repo;
  final String branch;

  /// Text contents at commit time. Kept for older saved state and for showing
  /// an offline diff; binary files are represented by [hashes].
  final Map<String, String> files;

  /// Git blob ids for every file in the commit. This is what keeps a 20 MB
  /// keystore or image from being read as a string.
  final Map<String, String> hashes;

  /// Paths the commit removes from the branch.
  final List<String> deleted;

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
        'hashes': hashes,
        'deleted': deleted,
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
      files: _stringMap(json['files']),
      hashes: _stringMap(json['hashes']),
      deleted: (json['deleted'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

/// Persisted inside `.praxis/push.json` in the project. `baseline` holds remote
/// text for offline diffs; `hashes` holds a Git blob id for every remote file,
/// including binaries. Pending commits are local commit objects whose ref has
/// not been updated yet.
class PushState {
  const PushState({
    this.owner = '',
    this.repo = '',
    this.branch = 'main',
    this.baseline = const {},
    this.hashes = const {},
    this.baseHashes = const {},
    this.pending = const [],
    this.synced = false,
  });

  final String owner;
  final String repo;
  final String branch;
  final Map<String, String> baseline;

  /// The remote tree at the last comparison, pull or push.
  final Map<String, String> hashes;

  /// The merge base: the contents that were on this device when the branch was
  /// last synced. A file changed only on GitHub is still equal to this base, so
  /// it is pulled instead of being reported as a local edit. Empty means "no
  /// merge base yet", and comparisons fall back to the remote tree.
  final Map<String, String> baseHashes;
  final List<PendingCommit> pending;

  /// Whether this target has been compared with the remote branch. Needed for
  /// an empty repository, where `baseline` and `hashes` are both legitimately
  /// empty.
  final bool synced;

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
    Map<String, String>? hashes,
    Map<String, String>? baseHashes,
    List<PendingCommit>? pending,
    bool? synced,
  }) =>
      PushState(
        owner: owner ?? this.owner,
        repo: repo ?? this.repo,
        branch: branch ?? this.branch,
        baseline: baseline ?? this.baseline,
        hashes: hashes ?? this.hashes,
        baseHashes: baseHashes ?? this.baseHashes,
        pending: pending ?? this.pending,
        synced: synced ?? this.synced,
      );

  /// Merge base for every path. Until a real base is stored (older saves),
  /// comparing against the remote tree is the only useful answer.
  Map<String, String> get comparisonBase =>
      baseHashes.isEmpty ? hashes : baseHashes;

  PushState withPending(PendingCommit commit) =>
      copyWith(pending: [...pending, commit]);

  PushState withoutPending(Iterable<String> shas) {
    final drop = shas.toSet();
    return copyWith(
      pending: pending.where((commit) => !drop.contains(commit.sha)).toList(),
    );
  }

  PushState withBaseline(
    Map<String, String> files, {
    Map<String, String>? hashes,
  }) {
    final mergedText = Map<String, String>.from(baseline)..addAll(files);
    final mergedHashes = Map<String, String>.from(this.hashes)
      ..addAll(hashes ?? const {});
    return copyWith(baseline: mergedText, hashes: mergedHashes);
  }

  /// Replaces the baseline with a complete remote snapshot. Used after clone or
  /// pull, where files removed remotely must also disappear locally.
  PushState withSnapshot(
    Map<String, String> files,
    Map<String, String> hashes,
  ) =>
      copyWith(
        baseline: Map<String, String>.from(files),
        hashes: Map<String, String>.from(hashes),
        baseHashes: Map<String, String>.from(hashes),
        synced: true,
      );

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'repo': repo,
        'branch': branch,
        'baseline': baseline,
        'hashes': hashes,
        'baseHashes': baseHashes,
        'pending': pending.map((commit) => commit.toJson()).toList(),
        'synced': synced,
      };

  static PushState fromJson(Map<String, dynamic> json) {
    final baseline = _stringMap(json['baseline']);
    final hashes = _stringMap(json['hashes']);
    // Saves written before the merge base was tracked compared against the
    // remote, so the stored remote tree is the correct starting point.
    final baseHashes = json.containsKey('baseHashes')
        ? _stringMap(json['baseHashes'])
        : hashes;
    return PushState(
      owner: json['owner'] as String? ?? '',
      repo: json['repo'] as String? ?? '',
      branch: json['branch'] as String? ?? 'main',
      baseline: baseline,
      hashes: hashes,
      baseHashes: baseHashes,
      pending: [
        for (final item in (json['pending'] as List? ?? const []))
          if (item is Map)
            if (PendingCommit.fromJson(item.cast<String, dynamic>())
                case final commit?)
              commit,
      ],
      synced:
          json['synced'] is bool ? json['synced'] as bool : hashes.isNotEmpty,
    );
  }
}

Map<String, String> _stringMap(Object? raw) =>
    (raw as Map?)?.map((key, value) => MapEntry('$key', '$value')) ??
    const <String, String>{};

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
