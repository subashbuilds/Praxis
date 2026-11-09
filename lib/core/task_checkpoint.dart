import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

enum TaskCheckpointStatus { running, resumable, completed }

extension TaskCheckpointStatusX on TaskCheckpointStatus {
  String get wire => name;

  static TaskCheckpointStatus parse(String? value) =>
      TaskCheckpointStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => TaskCheckpointStatus.resumable,
      );
}

/// A completed tool call, stored only as a one-way fingerprint and a short
/// label. File contents and command output are never written to a checkpoint.
class CheckpointAction {
  const CheckpointAction({
    required this.fingerprint,
    required this.tool,
    required this.label,
  });

  final String fingerprint;
  final String tool;
  final String label;

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'tool': tool,
        'label': label,
      };

  static CheckpointAction? fromJson(Map<String, dynamic> json) {
    final fingerprint = json['fingerprint'] as String? ?? '';
    if (fingerprint.isEmpty) return null;
    return CheckpointAction(
      fingerprint: fingerprint,
      tool: json['tool'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }
}

class CheckpointTurn {
  const CheckpointTurn({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, dynamic> toJson() => {'role': role, 'text': text};

  static CheckpointTurn? fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String? ?? '';
    final text = json['text'] as String? ?? '';
    if (role.isEmpty || text.isEmpty) return null;
    return CheckpointTurn(role: role, text: text);
  }
}

/// A resumable snapshot of one agent task. It deliberately contains no API
/// keys, credentials, full tool output or full file contents. Text is truncated
/// and redacted before it reaches disk.
class TaskCheckpoint {
  TaskCheckpoint({
    required this.taskId,
    required this.projectId,
    required this.providerId,
    required this.providerName,
    required this.model,
    required this.originalPrompt,
    required this.createdAt,
    required this.updatedAt,
    this.status = TaskCheckpointStatus.running,
    this.completed = const [],
    this.pendingStep = '',
    this.lastError = '',
    this.completedActions = const [],
    this.changedFiles = const {},
    this.gitBranch = '',
    this.gitPaths = const [],
    this.conversationTail = const [],
  });

  final String taskId;
  final String projectId;
  final String providerId;
  final String providerName;
  final String model;
  final String originalPrompt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TaskCheckpointStatus status;
  final List<String> completed;
  final String pendingStep;
  final String lastError;
  final List<CheckpointAction> completedActions;

  /// Path to a short digest of the file after the checkpoint. Digests are not
  /// secrets and let resume detect edits made outside the app.
  final Map<String, String> changedFiles;
  final String gitBranch;
  final List<String> gitPaths;
  final List<CheckpointTurn> conversationTail;

  bool get resumable => status == TaskCheckpointStatus.resumable;

  String get summary {
    final done =
        completed.isEmpty ? 'No completed steps recorded.' : completed.last;
    final left =
        pendingStep.isEmpty ? 'Continue the original request.' : pendingStep;
    return 'Completed: $done\nRemaining: $left';
  }

  TaskCheckpoint copyWith({
    String? taskId,
    String? projectId,
    String? providerId,
    String? providerName,
    String? model,
    String? originalPrompt,
    DateTime? createdAt,
    DateTime? updatedAt,
    TaskCheckpointStatus? status,
    List<String>? completed,
    String? pendingStep,
    String? lastError,
    List<CheckpointAction>? completedActions,
    Map<String, String>? changedFiles,
    String? gitBranch,
    List<String>? gitPaths,
    List<CheckpointTurn>? conversationTail,
  }) =>
      TaskCheckpoint(
        taskId: taskId ?? this.taskId,
        projectId: projectId ?? this.projectId,
        providerId: providerId ?? this.providerId,
        providerName: providerName ?? this.providerName,
        model: model ?? this.model,
        originalPrompt: originalPrompt ?? this.originalPrompt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        status: status ?? this.status,
        completed: completed ?? this.completed,
        pendingStep: pendingStep ?? this.pendingStep,
        lastError: lastError ?? this.lastError,
        completedActions: completedActions ?? this.completedActions,
        changedFiles: changedFiles ?? this.changedFiles,
        gitBranch: gitBranch ?? this.gitBranch,
        gitPaths: gitPaths ?? this.gitPaths,
        conversationTail: conversationTail ?? this.conversationTail,
      );

  TaskCheckpoint withAction(CheckpointAction action) {
    if (completedActions
        .any((item) => item.fingerprint == action.fingerprint)) {
      return this;
    }
    return copyWith(completedActions: [...completedActions, action]);
  }

  TaskCheckpoint withChangedFile(String path, String digest) {
    if (path.isEmpty) return this;
    return copyWith(changedFiles: {...changedFiles, path: digest});
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'projectId': projectId,
        'providerId': providerId,
        'providerName': providerName,
        'model': model,
        'originalPrompt': originalPrompt,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'status': status.wire,
        'completed': completed,
        'pendingStep': pendingStep,
        'lastError': lastError,
        'completedActions':
            completedActions.map((action) => action.toJson()).toList(),
        'changedFiles': changedFiles,
        'gitBranch': gitBranch,
        'gitPaths': gitPaths,
        'conversationTail':
            conversationTail.map((turn) => turn.toJson()).toList(),
      };

  static TaskCheckpoint? fromJson(Map<String, dynamic> json) {
    final taskId = json['taskId'] as String? ?? '';
    final projectId = json['projectId'] as String? ?? '';
    if (taskId.isEmpty || projectId.isEmpty) return null;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (createdAt == null || updatedAt == null) return null;
    final actions = json['completedActions'];
    final turns = json['conversationTail'];
    final changed = json['changedFiles'];
    final gitPaths = json['gitPaths'];
    final completed = json['completed'];
    return TaskCheckpoint(
      taskId: taskId,
      projectId: projectId,
      providerId: json['providerId'] as String? ?? '',
      providerName: json['providerName'] as String? ?? 'Provider',
      model: json['model'] as String? ?? '',
      originalPrompt: json['originalPrompt'] as String? ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      status: TaskCheckpointStatusX.parse(json['status'] as String?),
      completed:
          completed is List ? completed.whereType<String>().toList() : const [],
      pendingStep: json['pendingStep'] as String? ?? '',
      lastError: json['lastError'] as String? ?? '',
      completedActions: [
        if (actions is List)
          for (final item in actions)
            if (item is Map)
              if (CheckpointAction.fromJson(item.cast<String, dynamic>())
                  case final action?)
                action,
      ],
      changedFiles: changed is Map
          ? {
              for (final entry in changed.entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value as String,
            }
          : const {},
      gitBranch: json['gitBranch'] as String? ?? '',
      gitPaths:
          gitPaths is List ? gitPaths.whereType<String>().toList() : const [],
      conversationTail: [
        if (turns is List)
          for (final item in turns)
            if (item is Map)
              if (CheckpointTurn.fromJson(item.cast<String, dynamic>())
                  case final turn?)
                turn,
      ],
    );
  }

  /// A hash is enough to recognise a repeated action without storing its
  /// arguments. A resumed model can therefore be told to skip only calls whose
  /// exact arguments already completed before the interruption.
  static String actionFingerprint(
          String tool, Map<String, dynamic> arguments) =>
      sha256.convert(utf8.encode('$tool:${jsonEncode(arguments)}')).toString();

  static String digestText(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static String sanitize(String text, {int maxLength = 1200}) {
    var result = text;
    final patterns = <RegExp>[
      RegExp(r'sk-[A-Za-z0-9_-]{12,}'),
      RegExp(r'gh[pousr]_[A-Za-z0-9_]{20,}'),
      RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
      RegExp(r'glpat-[A-Za-z0-9_-]{16,}'),
      RegExp(r'Bearer\s+[A-Za-z0-9._-]+', caseSensitive: false),
      RegExp(
        r'(api[_-]?key|token|secret|password|passwd|authorization)\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      RegExp(r'[A-Fa-f0-9]{40,}'),
    ];
    for (final pattern in patterns) {
      result = result.replaceAll(pattern, '[redacted]');
    }
    result = result.trim();
    if (result.length > maxLength) {
      result = '${result.substring(0, maxLength)}…';
    }
    return result;
  }
}

abstract class TaskCheckpointStore {
  Future<void> save(TaskCheckpoint checkpoint);
  Future<TaskCheckpoint?> latestFor(String projectId);
  Future<List<TaskCheckpoint>> loadAll();
  Future<void> remove(String taskId);
  Future<void> clear();
}

class FileTaskCheckpointStore implements TaskCheckpointStore {
  FileTaskCheckpointStore(this.directory);

  final Directory directory;

  File get _file => File('${directory.path}/checkpoints.json');

  Future<void> prepare() => directory.create(recursive: true);

  @override
  Future<void> save(TaskCheckpoint checkpoint) async {
    await prepare();
    final all = [...await loadAll()];
    all.removeWhere((item) => item.taskId == checkpoint.taskId);
    all.add(checkpoint);
    // Keep the newest 20 tasks per project. Older snapshots are not useful and
    // would grow the store forever.
    final grouped = <String, List<TaskCheckpoint>>{};
    for (final item in all) {
      grouped.putIfAbsent(item.projectId, () => []).add(item);
    }
    final kept = <TaskCheckpoint>[];
    for (final list in grouped.values) {
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      kept.addAll(list.take(20));
    }
    kept.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode(kept.map((item) => item.toJson()).toList()),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  @override
  Future<TaskCheckpoint?> latestFor(String projectId) async {
    final all = await loadAll();
    TaskCheckpoint? latest;
    for (final item in all) {
      if (item.projectId != projectId) continue;
      if (latest == null || item.updatedAt.isAfter(latest.updatedAt)) {
        latest = item;
      }
    }
    return latest;
  }

  @override
  Future<List<TaskCheckpoint>> loadAll() async {
    if (!await _file.exists()) return const [];
    try {
      final raw = jsonDecode(await _file.readAsString());
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            if (TaskCheckpoint.fromJson(item.cast<String, dynamic>())
                case final checkpoint?)
              checkpoint,
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> remove(String taskId) async {
    final all = [...await loadAll()]
      ..removeWhere((item) => item.taskId == taskId);
    await prepare();
    await _file.writeAsString(
      jsonEncode(all.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  @override
  Future<void> clear() async {
    if (await _file.exists()) await _file.delete();
  }
}

class MemoryTaskCheckpointStore implements TaskCheckpointStore {
  final List<TaskCheckpoint> _items = [];

  List<TaskCheckpoint> get items => List.unmodifiable(_items);

  @override
  Future<void> save(TaskCheckpoint checkpoint) async {
    _items.removeWhere((item) => item.taskId == checkpoint.taskId);
    _items.add(checkpoint);
  }

  @override
  Future<TaskCheckpoint?> latestFor(String projectId) async {
    TaskCheckpoint? latest;
    for (final item in _items) {
      if (item.projectId != projectId) continue;
      if (latest == null || item.updatedAt.isAfter(latest.updatedAt)) {
        latest = item;
      }
    }
    return latest;
  }

  @override
  Future<List<TaskCheckpoint>> loadAll() async => List.unmodifiable(_items);

  @override
  Future<void> remove(String taskId) async {
    _items.removeWhere((item) => item.taskId == taskId);
  }

  @override
  Future<void> clear() async => _items.clear();
}
