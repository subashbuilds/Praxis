import 'dart:convert';
import 'dart:io';

import 'ai.dart';

enum AgentOutcome {
  completed,
  userCancelled,
  quotaError,
  error,
  loopDetected,
}

extension AgentOutcomeX on AgentOutcome {
  String get wire => switch (this) {
        AgentOutcome.completed => 'completed',
        AgentOutcome.userCancelled => 'user_cancelled',
        AgentOutcome.quotaError => 'quota_error',
        AgentOutcome.error => 'error',
        AgentOutcome.loopDetected => 'loop_detected',
      };

  String get label => switch (this) {
        AgentOutcome.completed => 'completed',
        AgentOutcome.userCancelled => 'cancelled',
        AgentOutcome.quotaError => 'quota error',
        AgentOutcome.error => 'error',
        AgentOutcome.loopDetected => 'loop detected',
      };
}

AgentOutcome? agentOutcomeFromWire(String? value) {
  for (final outcome in AgentOutcome.values) {
    if (outcome.wire == value) return outcome;
  }
  return null;
}

String agentOutcomeLabel(AgentOutcome? outcome) =>
    outcome?.label ?? 'incomplete';

enum RoundType { explore, edit, verify, retry, other }

extension RoundTypeX on RoundType {
  String get wire => switch (this) {
        RoundType.explore => 'explore',
        RoundType.edit => 'edit',
        RoundType.verify => 'verify',
        RoundType.retry => 'retry',
        RoundType.other => 'other',
      };

  String get label => switch (this) {
        RoundType.explore => 'explore',
        RoundType.edit => 'edit',
        RoundType.verify => 'verify',
        RoundType.retry => 'retry',
        RoundType.other => 'other',
      };
}

RoundType roundTypeFromWire(String? value) {
  for (final type in RoundType.values) {
    if (type.wire == value) return type;
  }
  return RoundType.other;
}

/// One model HTTP request. Arguments, prompts, file contents and secrets are
/// deliberately absent: only names and counts are recorded.
class AgentRound {
  const AgentRound({
    required this.taskId,
    required this.roundIndex,
    required this.at,
    required this.provider,
    required this.model,
    required this.toolNames,
    required this.type,
    required this.repeatedCall,
    this.inputTokens,
    this.outputTokens,
    this.finishReason = '',
  });

  final String taskId;
  final int roundIndex;
  final DateTime at;
  final String provider;
  final String model;
  final int? inputTokens;
  final int? outputTokens;
  final List<String> toolNames;
  final RoundType type;
  final bool repeatedCall;
  final String finishReason;

  int get toolCount => toolNames.length;

  Map<String, dynamic> toJson() => {
        'type': 'round',
        'taskId': taskId,
        'roundIndex': roundIndex,
        'at': at.toUtc().toIso8601String(),
        'provider': provider,
        'model': model,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'toolNames': toolNames,
        'toolCount': toolCount,
        'roundType': type.wire,
        'repeatedCall': repeatedCall,
        'finishReason': finishReason,
      };

  static AgentRound? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (at == null) return null;
    final names = json['toolNames'];
    return AgentRound(
      taskId: json['taskId'] as String? ?? '',
      roundIndex: json['roundIndex'] as int? ?? 0,
      at: at,
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      inputTokens: json['inputTokens'] as int?,
      outputTokens: json['outputTokens'] as int?,
      toolNames: names is List ? names.whereType<String>().toList() : const [],
      type: roundTypeFromWire(json['roundType'] as String?),
      repeatedCall: json['repeatedCall'] as bool? ?? false,
      finishReason: json['finishReason'] as String? ?? '',
    );
  }
}

/// One agent task: its model requests and its terminal outcome, if it reached
/// one before the app closed.
class AgentTask {
  AgentTask({
    required this.taskId,
    required List<AgentRound> rounds,
    this.outcome,
  }) : rounds = List<AgentRound>.unmodifiable(rounds);

  final String taskId;
  final List<AgentRound> rounds;
  final AgentOutcome? outcome;

  int get totalRounds => rounds.length;
  int get repeatedCalls => rounds.where((round) => round.repeatedCall).length;

  int? get firstEditIndex {
    for (final round in rounds) {
      if (round.type == RoundType.edit) return round.roundIndex;
    }
    return null;
  }

  int get roundsBeforeFirstEdit => firstEditIndex ?? rounds.length;

  DateTime? get startedAt => rounds.isEmpty ? null : rounds.first.at;
  DateTime? get finishedAt => rounds.isEmpty ? null : rounds.last.at;

  Map<RoundType, int> get roundsByType {
    final counts = <RoundType, int>{};
    for (final round in rounds) {
      counts[round.type] = (counts[round.type] ?? 0) + 1;
    }
    return counts;
  }

  int get inputTokens => rounds.fold(
        0,
        (sum, round) => sum + (round.inputTokens ?? 0),
      );

  int get outputTokens => rounds.fold(
        0,
        (sum, round) => sum + (round.outputTokens ?? 0),
      );
}

class AgentRoundStats {
  AgentRoundStats(Iterable<AgentTask> tasks)
      : tasks = List<AgentTask>.unmodifiable(tasks) {
    for (final task in this.tasks) {
      totalRounds += task.totalRounds;
      repeatedCalls += task.repeatedCalls;
      inputTokens += task.inputTokens;
      outputTokens += task.outputTokens;
      roundsBeforeFirstEdit += task.roundsBeforeFirstEdit;
      for (final entry in task.roundsByType.entries) {
        byType[entry.key] = (byType[entry.key] ?? 0) + entry.value;
      }
      final outcome = task.outcome;
      final label = agentOutcomeLabel(outcome);
      outcomes[label] = (outcomes[label] ?? 0) + 1;
    }
  }

  final List<AgentTask> tasks;
  int totalRounds = 0;
  int repeatedCalls = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  int roundsBeforeFirstEdit = 0;
  final Map<RoundType, int> byType = {};
  final Map<String, int> outcomes = {};

  int get totalTasks => tasks.length;

  double get averageRounds => tasks.isEmpty ? 0 : totalRounds / tasks.length;

  double get averageRoundsBeforeFirstEdit =>
      tasks.isEmpty ? 0 : roundsBeforeFirstEdit / tasks.length;
}

/// Persistent seam. Production uses [FileRoundLog]; tests use [MemoryRoundLog].
abstract class RoundLogStore {
  Future<void> appendRound(AgentRound round);
  Future<void> finishTask(String taskId, AgentOutcome outcome);
  Future<List<AgentTask>> loadTasks();
  Future<void> clear();
}

class FileRoundLog implements RoundLogStore {
  FileRoundLog(this.directory);

  final Directory directory;

  File get _file => File('${directory.path}/agent_rounds.jsonl');

  Future<void> prepare() => directory.create(recursive: true);

  @override
  Future<void> appendRound(AgentRound round) async {
    await prepare();
    await _file.writeAsString(
      '${jsonEncode(round.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<void> finishTask(String taskId, AgentOutcome outcome) async {
    await prepare();
    await _file.writeAsString(
      '${jsonEncode({
            'type': 'end',
            'taskId': taskId,
            'at': DateTime.now().toUtc().toIso8601String(),
            'outcome': outcome.wire,
          })}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<List<AgentTask>> loadTasks() async {
    if (!await _file.exists()) return const [];
    final rounds = <String, List<AgentRound>>{};
    final outcomes = <String, AgentOutcome>{};
    final lines = await _file.readAsLines();
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic> json;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        json = decoded.cast<String, dynamic>();
      } catch (_) {
        continue;
      }
      final type = json['type'] as String? ?? 'round';
      if (type == 'round') {
        final round = AgentRound.fromJson(json);
        if (round == null || round.taskId.isEmpty) continue;
        rounds.putIfAbsent(round.taskId, () => []).add(round);
      } else if (type == 'end') {
        final taskId = json['taskId'] as String? ?? '';
        final outcome = agentOutcomeFromWire(json['outcome'] as String?);
        if (taskId.isNotEmpty && outcome != null) outcomes[taskId] = outcome;
      }
    }
    return _buildTasks(rounds, outcomes);
  }

  @override
  Future<void> clear() async {
    if (await _file.exists()) await _file.delete();
  }
}

class MemoryRoundLog implements RoundLogStore {
  final List<AgentRound> _rounds = [];
  final Map<String, AgentOutcome> _outcomes = {};

  List<AgentRound> get rounds => List<AgentRound>.unmodifiable(_rounds);
  Map<String, AgentOutcome> get outcomes => Map.unmodifiable(_outcomes);

  @override
  Future<void> appendRound(AgentRound round) async {
    _rounds.add(round);
  }

  @override
  Future<void> finishTask(String taskId, AgentOutcome outcome) async {
    _outcomes[taskId] = outcome;
  }

  @override
  Future<List<AgentTask>> loadTasks() async =>
      _buildTasks(_groupByTask(_rounds), _outcomes);

  @override
  Future<void> clear() async {
    _rounds.clear();
    _outcomes.clear();
  }
}

List<AgentTask> _buildTasks(
  Map<String, List<AgentRound>> rounds,
  Map<String, AgentOutcome> outcomes,
) {
  final tasks = <AgentTask>[];
  for (final entry in rounds.entries) {
    if (entry.key.isEmpty || entry.value.isEmpty) continue;
    final sorted = [...entry.value]..sort((a, b) {
        final index = a.roundIndex.compareTo(b.roundIndex);
        if (index != 0) return index;
        return a.at.compareTo(b.at);
      });
    tasks.add(AgentTask(
      taskId: entry.key,
      rounds: sorted,
      outcome: outcomes[entry.key],
    ));
  }
  tasks.sort((a, b) {
    final aAt = a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bAt = b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bAt.compareTo(aAt);
  });
  return tasks;
}

Map<String, List<AgentRound>> _groupByTask(List<AgentRound> rounds) {
  final grouped = <String, List<AgentRound>>{};
  for (final round in rounds) {
    grouped.putIfAbsent(round.taskId, () => []).add(round);
  }
  return grouped;
}

/// Heuristic only. It never sees prompts or file contents.
RoundType classifyRound(
  List<AiToolCall> calls, {
  bool previousToolFailed = false,
}) {
  if (previousToolFailed) return RoundType.retry;
  if (calls.isEmpty) return RoundType.other;

  var sawEdit = false;
  var sawVerify = false;
  var sawExplore = false;
  for (final call in calls) {
    if (const {
      'write_file',
      'edit_file',
      'download_file',
      'install_skill',
    }.contains(call.name)) {
      sawEdit = true;
      continue;
    }
    if (call.name == 'read_file' || call.name == 'list_files') {
      sawExplore = true;
      continue;
    }
    if (call.name == 'run_command') {
      final command = call.arguments['command'] as String? ?? '';
      if (_verifyPattern.hasMatch(command)) {
        sawVerify = true;
      } else if (_editPattern.hasMatch(command)) {
        sawEdit = true;
      } else if (_explorePattern.hasMatch(command)) {
        sawExplore = true;
      }
    }
  }
  if (sawEdit) return RoundType.edit;
  if (sawVerify) return RoundType.verify;
  if (sawExplore) return RoundType.explore;
  return RoundType.other;
}

final _verifyPattern = RegExp(
  r'\b(flutter test|flutter analyze|dart analyze|npm test|yarn test|pnpm test|pytest|go test|cargo test|typecheck|tsc|build|lint|compile)\b',
  caseSensitive: false,
);

final _explorePattern = RegExp(
  r'\b(ls|find|grep|rg|cat|head|tail|wc|pwd|sed|awk|git status|git diff)\b',
  caseSensitive: false,
);

final _editPattern = RegExp(
  r'\b(sed\s+-i|tee|touch|mkdir|rm|mv|cp)\b',
  caseSensitive: false,
);
