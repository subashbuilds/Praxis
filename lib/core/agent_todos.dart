import 'dart:convert';

import 'vfs.dart';

enum AgentTodoStatus { pending, inProgress, completed }

extension AgentTodoStatusX on AgentTodoStatus {
  String get wire => switch (this) {
        AgentTodoStatus.pending => 'pending',
        AgentTodoStatus.inProgress => 'in_progress',
        AgentTodoStatus.completed => 'completed',
      };

  bool get done => this == AgentTodoStatus.completed;

  static AgentTodoStatus parse(Object? value) {
    if (value == 'completed' || value == 'done') {
      return AgentTodoStatus.completed;
    }
    if (value == 'in_progress' || value == 'active') {
      return AgentTodoStatus.inProgress;
    }
    return AgentTodoStatus.pending;
  }
}

/// One item in the agent-maintained task checklist. The list is short, ordered
/// and persisted so it survives a paused or interrupted response.
class AgentTodo {
  const AgentTodo({required this.text, this.status = AgentTodoStatus.pending});

  final String text;
  final AgentTodoStatus status;

  bool get done => status.done;

  AgentTodo copyWith({String? text, AgentTodoStatus? status}) => AgentTodo(
        text: text ?? this.text,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'status': status.wire,
      };

  static AgentTodo? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = '${json['text'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;
    return AgentTodo(
      text: text.length > 160 ? '${text.substring(0, 157)}...' : text,
      status: AgentTodoStatusX.parse(json['status']),
    );
  }
}

/// Stored under `.praxis`, so the checklist is app state, not project content,
/// and is never offered to the model as a file.
class ProjectTodosStore {
  const ProjectTodosStore._();

  static const path = '.praxis/todos.json';

  static Future<List<AgentTodo>> load(ProjectFs fs) async {
    try {
      if (!await fs.exists(path)) return const [];
      final decoded = jsonDecode(await fs.read(path));
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (AgentTodo.fromJson(item) case final todo?) todo,
      ].take(12).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(ProjectFs fs, List<AgentTodo> todos) => fs.write(
        path,
        jsonEncode(todos.take(12).map((todo) => todo.toJson()).toList()),
      );
}
