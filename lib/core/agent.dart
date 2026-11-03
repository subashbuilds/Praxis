import '../models.dart';
import 'ai.dart';
import 'shell.dart';
import 'vfs.dart';

enum AgentEventKind { text, tool, error }

class AgentEvent {
  const AgentEvent({
    required this.kind,
    this.text = '',
    this.tool = '',
    this.detail = '',
    this.ok = true,
  });

  const AgentEvent.text(String value)
      : kind = AgentEventKind.text,
        text = value,
        tool = '',
        detail = '',
        ok = true;

  const AgentEvent.tool({
    required this.tool,
    required this.detail,
    required this.text,
  })  : kind = AgentEventKind.tool,
        ok = true;

  const AgentEvent.error(String value)
      : kind = AgentEventKind.error,
        text = value,
        tool = '',
        detail = '',
        ok = false;

  final AgentEventKind kind;
  final String text;
  final String tool;
  final String detail;
  final bool ok;
}

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
        'No node, python, git or flutter binaries exist on the device.',
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
    this.maxRounds = 6,
  });

  final AiClient client;
  final ProviderConfig provider;
  final ProjectFs fs;
  final Shell shell;
  final List<Skill> skills;
  final void Function(AgentEvent event) onEvent;
  final int maxRounds;

  Future<void> run({
    required List<AiTurn> history,
    required String prompt,
    bool Function()? isCancelled,
  }) async {
    final system = await _systemPrompt();
    final turns = <AiTurn>[...history, AiTurn.user(prompt)];

    for (var round = 0; round < maxRounds; round++) {
      if (isCancelled?.call() ?? false) return;
      final reply = await client.complete(
        provider: provider,
        system: system,
        turns: turns,
        tools: kAgentTools,
      );
      if (reply.calls.isEmpty) {
        final text = reply.text.trim();
        onEvent(AgentEvent.text(
            text.isEmpty ? 'Done — no changes were needed.' : text));
        return;
      }
      turns.add(AiTurn.assistant(reply.text, reply.calls));
      if (reply.text.trim().isNotEmpty) {
        onEvent(AgentEvent.text(reply.text.trim()));
      }
      for (final call in reply.calls) {
        if (isCancelled?.call() ?? false) return;
        final result = await _execute(call);
        onEvent(AgentEvent.tool(
          tool: call.name,
          detail: _detail(call),
          text: result,
        ));
        turns.add(AiTurn.tool(call.id, call.name, result));
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
You work on a real project folder on the device. The user sees your replies and
every tool call in a chat next to the code, a terminal and a live preview.

Work with the tools. Do not claim to have changed a file unless write_file
succeeded. Keep edits focused and complete: write_file replaces the whole file,
so send full contents. Prefer a small number of decisive edits over exploration.

Project files:
$files

Constraints:
- No Node, Python, Flutter or git binaries exist. run_command only touches files.
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

  Future<String> _execute(AiToolCall call) async {
    try {
      switch (call.name) {
        case 'list_files':
          final path = (call.arguments['path'] as String? ?? '').trim();
          final entries = await fs.list(path: path);
          if (entries.isEmpty) return '(empty)';
          return entries
              .map((e) => e.isDir ? '${e.path}/' : '${e.path} (${e.size} B)')
              .join('\n');
        case 'read_file':
          final path = (call.arguments['path'] as String? ?? '').trim();
          if (path.isEmpty) return 'Error: path is required';
          final content = await fs.read(path);
          return content.length > 16000
              ? '${content.substring(0, 16000)}\n… truncated'
              : content;
        case 'write_file':
          final path = (call.arguments['path'] as String? ?? '').trim();
          final content = call.arguments['content'] as String? ?? '';
          if (path.isEmpty) return 'Error: path is required';
          final bytes = await fs.write(path, content);
          return 'Wrote $bytes bytes to $path';
        case 'run_command':
          final command = (call.arguments['command'] as String? ?? '').trim();
          if (command.isEmpty) return 'Error: command is required';
          final result = await shell.run(command);
          if (result.lines.isEmpty) return '(no output)';
          final output = result.lines
              .map((line) => line.text)
              .where((line) => line.isNotEmpty)
              .join('\n');
          return output.length > 8000
              ? '${output.substring(0, 8000)}\n… truncated'
              : output;
        default:
          return 'Error: unknown tool ${call.name}';
      }
    } on FsError catch (error) {
      return 'Error: ${error.message}';
    } catch (error) {
      return 'Error: $error';
    }
  }

  String _detail(AiToolCall call) {
    final args = call.arguments;
    switch (call.name) {
      case 'write_file':
        final content = args['content'] as String? ?? '';
        return '${args['path'] ?? '?'} · ${content.length} B';
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
