import 'dart:convert';

import 'ai.dart';

/// Returns null when [call] matches the tool schema, or a short, actionable
/// message the model can use to correct the call in one round.
String? validateToolArguments(
  AiToolCall call,
  Iterable<AiToolSpec> tools,
) {
  AiToolSpec? spec;
  for (final candidate in tools) {
    if (candidate.name == call.name) {
      spec = candidate;
      break;
    }
  }
  if (spec == null) {
    return 'Unknown tool "${call.name}". Use one of: '
        '${tools.map((tool) => tool.name).join(', ')}.';
  }
  final parameters = spec.parameters;
  final required = parameters['required'];
  if (required is List) {
    for (final name in required.whereType<String>()) {
      if (!call.arguments.containsKey(name)) {
        return 'Invalid arguments for ${call.name}: "$name" is required. '
            'Expected ${_shape(spec)}.';
      }
    }
  }
  final properties = parameters['properties'];
  if (properties is Map) {
    for (final entry in properties.entries) {
      if (!call.arguments.containsKey(entry.key)) continue;
      final schema = entry.value;
      if (schema is! Map) continue;
      final problem = _validateValue(
        call.arguments[entry.key],
        schema.cast<String, dynamic>(),
        entry.key,
      );
      if (problem != null) {
        return 'Invalid arguments for ${call.name}: $problem. '
            'Expected ${_shape(spec)}.';
      }
    }
  }
  if (call.name == 'run_commands') {
    final commands = call.arguments['commands'];
    if (commands is List && commands.isEmpty) {
      return 'Invalid arguments for run_commands: "commands" cannot be empty. '
          'Provide between 1 and 8 shell commands.';
    }
    if (commands is List && commands.length > 8) {
      return 'Invalid arguments for run_commands: at most 8 commands can run '
          'in one call. Split the work into smaller calls.';
    }
  }
  if (call.name == 'read_files') {
    final paths = call.arguments['paths'];
    if (paths is List && paths.isEmpty) {
      return 'Invalid arguments for read_files: "paths" cannot be empty. '
          'Pass one or more path strings.';
    }
  }
  return null;
}

String? _validateValue(
    Object? value, Map<String, dynamic> schema, String name) {
  final type = schema['type'];
  if (type == 'string' && value is! String) {
    return '"$name" must be a string';
  }
  if (type == 'integer' && value is! int) {
    return '"$name" must be an integer';
  }
  if (type == 'boolean' && value is! bool) {
    return '"$name" must be true or false';
  }
  if (type == 'array') {
    if (value is! List) return '"$name" must be an array';
    final items = schema['items'];
    if (items is Map) {
      final itemSchema = items.cast<String, dynamic>();
      for (var index = 0; index < value.length; index++) {
        final problem =
            _validateValue(value[index], itemSchema, '$name[$index]');
        if (problem != null) return problem;
      }
    }
  }
  if (type == 'object' && value is! Map) {
    return '"$name" must be an object';
  }
  return null;
}

String _shape(AiToolSpec spec) {
  final parameters = spec.parameters;
  final properties = parameters['properties'];
  final required = parameters['required'];
  if (properties is! Map || properties.isEmpty) return '{}';
  final shape = <String, String>{};
  for (final entry in properties.entries) {
    final schema = entry.value;
    final type = schema is Map ? schema['type'] : null;
    shape['${entry.key}${required is List && required.contains(entry.key) ? '*' : ''}'] =
        type is String ? type : 'value';
  }
  return jsonEncode(shape);
}
