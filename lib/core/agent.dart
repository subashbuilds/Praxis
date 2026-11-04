import '../models.dart';
import 'ai.dart';
import 'diff.dart';
import 'shell.dart';
import 'vfs.dart';

enum AgentEventKind { text, tool, error }

class AgentEvent {
  const AgentEvent({
    required this.kind,
    this.text = '',
    this.tool = '',
    this.detail = '',
    this.thinking = '',
    this.patch = '',
    this.added = 0,
    this.removed = 0,
    this.ok = true,
  });

  const AgentEvent.text(String value, {this.thinking = ''})
      : kind = AgentEventKind.text,
        text = value,
        tool = '',
        detail = '',
        patch = '',
        added = 0,
        removed = 0,
        ok = true;

  const AgentEvent.tool({
    required this.tool,
    required this.detail,
    required this.text,
    this.patch = '',
    this.added = 0,
    this.removed = 0,
  })  : kind = AgentEventKind.tool,
        thinking = '',
        ok = true;

  const AgentEvent.error(String value)
      : kind = AgentEventKind.error,
        text = value,
        tool = '',
        detail = '',
        thinking = '',
        patch = '',
        added = 0,
        removed = 0,
        ok = false;

  final AgentEventKind kind;
  final String text;
  final String tool;
  final String detail;
  final String thinking;
  final String patch;
  final int added;
  final int removed;
  final bool ok;
}

/// Called when a provider says a key is out of quota. Returning a config with
/// another key or provider retries the same round; returning null stops.
typedef ProviderLimitHandler = Future<ProviderConfig?> Function(
  ProviderConfig current,
  AiProviderException error,
);

const kAgentTools = <AiToolSpec>[
  AiToolSpec(
    name: 'list_files',
    description: 'List every file in the project, recursively, with sizes.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Directory relative to the project root.'
        },
      },
    },
  ),
  AiToolSpec(
    name: 'read_file',
    description: 'Read a UTF-8 text file from the project.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'File path relative to the project root.'
        },
      },
      'required': ['path'],
    },
  ),
  AiToolSpec(
    name: 'write_file',
    description:
        'Create or overwrite a file with the complete new contents. Always send the whole file.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'File path relative to the project root.'
        },
        'content': {'type': 'string', 'description': 'Full file contents.'},
      },
      'required': ['path', 'content'],
    },
  ),
  AiToolSpec(
    name: 'run_command',
    description:
        'Run a shell command against the project files (ls, cat, grep, wc, tree, mkdir, mv, rm). '
        'The agent shell is sandboxed and has no node, python, git or flutter binaries.',
    parameters: {
      'type': 'object',
      'properties': {
        'command': {
          'type': 'string',
          'description': 'Command line to execute.'
        },
      },
      'required': ['command'],
    },
  ),
];

class Agent {
  Agent({
    required this.client,
    required this.provider,
    required this.fs,
    required this.shell,
    required this.skills,
    required this.onEvent,
    this.onProviderLimit,
    this.maxRounds = 6,
  });

  final AiClient client;
  final ProviderConfig provider;
  final ProjectFs fs;
  final Shell shell;
  final List<Skill> skills;
  final void Function(AgentEvent event) onEvent;
  final ProviderLimitHandler? onProviderLimit;
  final int maxRounds;

  Future<void> run({
    required List<AiTurn> history,
    required String prompt,
    bool Function()? isCancelled,
  }) async {
    final system = await _systemPrompt();
    final turns = <AiTurn>[...history, AiTurn.user(prompt)];
    var current = provider;

    for (var round = 0; round < maxRounds; round++) {
      if (isCancelled?.call() ?? false) return;

      AiReply reply;
      var switches = 0;
      while (true) {
        try {
          reply = await client.complete(
            provider: current,
            system: system,
            turns: turns,
            tools: kAgentTools,
          );
          break;
        } on AiProviderException catch (error) {
          final handler = onProviderLimit;
          if (!error.isLimit || handler == null || switches >= 3) rethrow;
          final next = await handler(current, error);
          if (next == null) rethrow;
          current = next;
          switches++;
        }
      }

      if (reply.calls.isEmpty) {
        final text = reply.text.trim();
        onEvent(AgentEvent.text(
          text.isEmpty ? 'Done — no changes were needed.' : text,
          thinking: reply.thinking,
        ));
        return;
      }
      turns.add(AiTurn.assistant(reply.text, reply.calls));
      if (reply.text.trim().isNotEmpty || reply.thinking.trim().isNotEmpty) {
        onEvent(AgentEvent.text(
          reply.text.trim(),
          thinking: reply.thinking.trim(),
        ));
      }
      for (final call in reply.calls) {
        if (isCancelled?.call() ?? false) return;
        final result = await _execute(call);
        onEvent(AgentEvent.tool(
          tool: call.name,
          detail: _detail(call),
          text: result.text,
          patch: result.diff?.toJson() ?? '',
          added: result.diff?.added ?? 0,
          removed: result.diff?.removed ?? 0,
        ));
        turns.add(AiTurn.tool(call.id, call.name, result.text));
      }
    }
    onEvent(const AgentEvent.error(
      'Stopped after 6 rounds of tool calls. Ask for a smaller step.',
    ));
  }

  Future<String> _systemPrompt() async {
    final files = await _fileTree();
    final skillText = skills
        .where((skill) => skill.enabled && skill.instructions.trim().isNotEmpty)
        .map((skill) => '- ${skill.name}: ${skill.instructions.trim()}')
        .join('\n');
    return '''
You are DevNest, an AI coding agent running on the user's Android phone.
You work on a real project folder on the device. The user sees your replies,
your reasoning behind a collapsed pill, and every tool call with its diff in a
chat next to the code, a terminal and a live preview.

Work with the tools. Do not claim to have changed a file unless write_file
succeeded. Keep edits focused and complete: write_file replaces the whole file,
so send full contents. Prefer a small number of decisive edits over exploration.

Project files:
$files

Constraints:
- Your run_command shell is sandboxed to file operations. The user has a
  separate real device shell; do not claim you can run git, node or python.
- A web project previews when it has an index.html; link its CSS and JS by
  relative path so the preview can load them.
- Secrets and API keys live in settings; never write them into project files.
${skillText.isEmpty ? '' : '\nSkills the user enabled:\n$skillText'}
''';
  }

  Future<String> _fileTree() async {
    try {
      final entries = await fs.list();
      if (entries.isEmpty) return '(empty project)';
      return entries
          .take(80)
          .map((entry) => entry.isDir
              ? '${entry.path}/'
              : '${entry.path} (${entry.size} B)')
          .join('\n');
    } on FsError {
      return '(project folder is empty)';
    }
  }

  Future<_ToolOutcome> _execute(AiToolCall call) async {
    try {
      switch (call.name) {
        case 'list_files':
          final path = (call.arguments['path'] as String? ?? '').trim();
          final entries = await fs.list(path: path);
          if (entries.isEmpty) return const _ToolOutcome('(empty)');
          return _ToolOutcome(entries
              .map((e) => e.isDir ? '${e.path}/' : '${e.path} (${e.size} B)')
              .join('\n'));
        case 'read_file':
          final path = (call.arguments['path'] as String? ?? '').trim();
          if (path.isEmpty) {
            return const _ToolOutcome('Error: path is required');
          }
          final content = await fs.read(path);
          return _ToolOutcome(content.length > 16000
              ? '${content.substring(0, 16000)}\n… truncated'
              : content);
        case 'write_file':
          final path = (call.arguments['path'] as String? ?? '').trim();
          final content = call.arguments['content'] as String? ?? '';
          if (path.isEmpty) {
            return const _ToolOutcome('Error: path is required');
          }
          final before = await fs.exists(path) ? await fs.read(path) : '';
          final bytes = await fs.write(path, content);
          final diff = computeDiff(before, content);
          return _ToolOutcome(
            'Wrote $bytes bytes to $path',
            diff: diff.isEmpty ? null : diff,
          );
        case 'run_command':
          final command = (call.arguments['command'] as String? ?? '').trim();
          if (command.isEmpty) {
            return const _ToolOutcome('Error: command is required');
          }
          final result = await shell.run(command);
          if (result.lines.isEmpty) return const _ToolOutcome('(no output)');
          final output = result.lines
              .map((line) => line.text)
              .where((line) => line.isNotEmpty)
              .join('\n');
          return _ToolOutcome(output.length > 8000
              ? '${output.substring(0, 8000)}\n… truncated'
              : output);
        default:
          return _ToolOutcome('Error: unknown tool ${call.name}');
      }
    } on FsError catch (error) {
      return _ToolOutcome('Error: ${error.message}');
    } catch (error) {
      return _ToolOutcome('Error: $error');
    }
  }

  String _detail(AiToolCall call) {
    final args = call.arguments;
    switch (call.name) {
      case 'write_file':
        return '${args['path'] ?? '?'}';
      case 'read_file':
        return '${args['path'] ?? '?'}';
      case 'run_command':
        return '${args['command'] ?? '?'}';
      case 'list_files':
        return (args['path'] as String? ?? '.').isEmpty
            ? '.'
            : '${args['path']}';
      default:
        return '';
    }
  }
}

class _ToolOutcome {
  const _ToolOutcome(this.text, {this.diff});
  final String text;
  final FileDiff? diff;
}
