import 'dart:convert';

import '../models.dart';
import 'ai.dart';
import 'diff.dart';
import 'file_types.dart';
import 'project_skills.dart';
import 'shell.dart';
import 'system_shell.dart';
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

typedef AgentFetchText = Future<String> Function(String url);
typedef AgentFetchBytes = Future<List<int>> Function(String url);
typedef AgentGitAction = Future<String> Function(String message);
typedef AgentPullAction = Future<String> Function();

const _baseAgentTools = <AiToolSpec>[
  AiToolSpec(
    name: 'list_files',
    description:
        'List project files with sizes. The project tree is already in the system prompt; '
        'use this only when you need a directory deeper than that listing.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'Directory relative to the project root.',
        },
      },
    },
  ),
  AiToolSpec(
    name: 'read_file',
    description:
        'Read a UTF-8 text file by line. Long files are paged: the result ends with the exact '
        'next offset. Never request the same path and offset twice; continue from that offset '
        'or work with the text already returned. Binary files are reported, not decoded.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'File path relative to the project root.',
        },
        'offset': {
          'type': 'integer',
          'description': 'First line to return, 1-based. Defaults to 1.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum number of lines to return. Defaults to 350.',
        },
      },
      'required': ['path'],
    },
  ),
  AiToolSpec(
    name: 'write_file',
    description:
        'Create a new UTF-8 file, or overwrite one when the whole content must change. '
        'For an existing large file, prefer edit_file so you send only the changed text.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'File path relative to the project root.',
        },
        'content': {'type': 'string', 'description': 'Full file contents.'},
      },
      'required': ['path', 'content'],
    },
  ),
  AiToolSpec(
    name: 'edit_file',
    description:
        'Change part of an existing UTF-8 file without resending the whole file. old_text '
        'must uniquely identify the text unless replace_all is true. Use this for surgical edits, '
        'especially in long README, source and config files.',
    parameters: {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': 'File path relative to the project root.',
        },
        'old_text': {
          'type': 'string',
          'description': 'Exact text to find, including indentation.',
        },
        'new_text': {
          'type': 'string',
          'description': 'Replacement text.',
        },
        'replace_all': {
          'type': 'boolean',
          'description': 'Replace every match instead of requiring one match.',
        },
      },
      'required': ['path', 'old_text', 'new_text'],
    },
  ),
  AiToolSpec(
    name: 'install_skill',
    description:
        'Install a reusable project skill at .praxis/skills/<name>/SKILL.md. Provide instructions, '
        'or provide source_url for a raw SKILL.md, GitHub file, GitHub folder or repository. '
        'Installed skills load into every future prompt for every provider.',
    parameters: {
      'type': 'object',
      'properties': {
        'name': {
          'type': 'string',
          'description': 'Short skill name, e.g. telegram-voice-notes.',
        },
        'description': {
          'type': 'string',
          'description': 'One line explaining when the skill should be used.',
        },
        'instructions': {
          'type': 'string',
          'description':
              'Complete Markdown instructions. May be omitted with source_url.',
        },
        'source_url': {
          'type': 'string',
          'description':
              'URL to a SKILL.md, GitHub file or folder, or repository.',
        },
      },
      'required': [],
    },
  ),
  AiToolSpec(
    name: 'run_command',
    description:
        'Run a command in the device shell inside the project. This is the real /system/bin/sh, '
        'not a file-ops imitation. Commands include ls, cat, grep, sed, awk, tar and any binary '
        'installed on the phone. node, npm, git and python are not bundled by Praxis; check with '
        'command -v before using them. Network commands work if curl or wget exists.',
    parameters: {
      'type': 'object',
      'properties': {
        'command': {
          'type': 'string',
          'description': 'Command line to execute.',
        },
      },
      'required': ['command'],
    },
  ),
];

const _gitPushTool = AiToolSpec(
  name: 'commit_and_push',
  description:
      'Commit all changed project files and push the current branch to the connected GitHub '
      'repository. Ask the user first in your reply; Praxis also shows a destination confirmation '
      'before anything leaves the device. Use only after the user explicitly asks to publish.',
  parameters: {
    'type': 'object',
    'properties': {
      'message': {
        'type': 'string',
        'description': 'Clear commit message describing the changes.',
      },
    },
    'required': ['message'],
  },
);

const _gitPullTool = AiToolSpec(
  name: 'pull_latest',
  description:
      'Pull the latest commit of the current GitHub branch into this project. Local edits are '
      'preserved when safe; conflicts stop the pull. The user confirms first.',
  parameters: {'type': 'object', 'properties': {}},
);

class Agent {
  Agent({
    required this.client,
    required this.provider,
    required this.fs,
    required this.shell,
    required this.skills,
    required this.onEvent,
    this.deviceShell,
    this.fetchText,
    this.fetchBytes,
    this.onCommitAndPush,
    this.onPullLatest,
    this.onProviderLimit,
    this.onTextDelta,
    this.onThinkingDelta,
    this.onToolStart,
    this.onReply,
    this.onDiscardLive,
    this.maxRounds = 24,
  });

  final AiClient client;
  final ProviderConfig provider;
  final ProjectFs fs;

  /// File-ops fallback used by unit tests and platforms without a process
  /// shell. In the app this is replaced by [deviceShell].
  final Shell shell;
  final SystemShell? deviceShell;
  final List<Skill> skills;
  final void Function(AgentEvent event) onEvent;
  final AgentFetchText? fetchText;
  final AgentFetchBytes? fetchBytes;
  final AgentGitAction? onCommitAndPush;
  final AgentPullAction? onPullLatest;
  final ProviderLimitHandler? onProviderLimit;
  final void Function(String delta)? onTextDelta;
  final void Function(String delta)? onThinkingDelta;
  final void Function(AiToolCall call)? onToolStart;
  final void Function(AiReply reply, ProviderConfig provider)? onReply;

  /// Clears streamed text when the agent has to retry a completion that made
  /// no file change. Without this, a premature "Done" would stay in the live
  /// reply above the corrective round.
  final void Function()? onDiscardLive;
  final int maxRounds;

  final Map<String, int> _readCache = {};
  String? _lastCallSignature;
  int _repeatedCalls = 0;

  List<AiToolSpec> get _tools => [
        ..._baseAgentTools,
        if (fetchBytes != null) _downloadTool,
        if (onCommitAndPush != null) _gitPushTool,
        if (onPullLatest != null) _gitPullTool,
      ];

  static const _downloadTool = AiToolSpec(
    name: 'download_file',
    description:
        'Download a URL into the project, preserving bytes. Use for images, assets, archives or '
        'skill files. Authorization for a connected GitHub account is added automatically.',
    parameters: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string', 'description': 'HTTP or HTTPS URL.'},
        'path': {
          'type': 'string',
          'description': 'Destination path relative to the project root.',
        },
      },
      'required': ['url', 'path'],
    },
  );

  Future<void> run({
    required List<AiTurn> history,
    required String prompt,
    bool Function()? isCancelled,
  }) async {
    final system = await _systemPrompt();
    final turns = <AiTurn>[...history, AiTurn.user(prompt)];
    var current = provider;
    var mutated = false;
    var completionNudges = 0;

    for (var round = 0; round < maxRounds; round++) {
      if (isCancelled?.call() ?? false) return;

      AiReply reply;
      var switches = 0;
      while (true) {
        try {
          reply = await client.stream(
            provider: current,
            system: system,
            turns: turns,
            tools: _tools,
            onText: onTextDelta,
            onThinking: onThinkingDelta,
          );
          onReply?.call(reply, current);
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
        if (!mutated &&
            completionNudges < 1 &&
            _looksLikeChangeRequest(prompt)) {
          completionNudges++;
          onDiscardLive?.call();
          turns.add(AiTurn.assistant(reply.text, const []));
          turns.add(const AiTurn.user(
            'You have not changed a file yet. Do not stop with a completion '
            'message. Use edit_file for an existing file or write_file for a '
            'new file now. Read only the specific range you still need. If the '
            'request genuinely requires no file change, state the evidence, '
            'but otherwise make the requested change.',
          ));
          continue;
        }
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
        final signature = '${call.name}:${jsonEncode(call.arguments)}';
        if (signature == _lastCallSignature) {
          _repeatedCalls++;
        } else {
          _lastCallSignature = signature;
          _repeatedCalls = 1;
        }
        if (_repeatedCalls >= 4) {
          onEvent(AgentEvent.error(
            'Stopped: the model repeated the same ${call.name} call four times. '
            'Try a more specific request, or send “continue” to resume with a different approach.',
          ));
          return;
        }
        onToolStart?.call(call);
        final result = await _execute(call);
        if (!mutated &&
            const {
              'write_file',
              'edit_file',
              'download_file',
              'install_skill',
            }.contains(call.name) &&
            !result.text.startsWith('Error')) {
          mutated = true;
        }
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
    onEvent(AgentEvent.error(
      'Paused after $maxRounds tool rounds. Send “continue” to keep going.',
    ));
  }

  bool _looksLikeChangeRequest(String prompt) {
    final text = prompt.toLowerCase();
    return RegExp(
      r'\b(add|change|edit|fix|update|implement|refactor|remove|delete|rename|move|create|write|replace|make|build|improve|polish|migrate|bump|generate|set|configure)\b',
    ).hasMatch(text);
  }

  Future<String> _systemPrompt() async {
    final files = await _fileTree();
    final installed = await _installedSkills();
    final skillText = [
      ...skills.where(
          (skill) => skill.enabled && skill.instructions.trim().isNotEmpty),
      ...installed,
    ]
        .map((skill) => '- ${skill.name}: ${skill.instructions.trim()}')
        .join('\n');
    final fullShell = deviceShell != null;
    return '''
You are Praxis, an AI coding agent running on the user's Android phone.
You work on a real project folder on the device. The user sees your replies,
your reasoning behind a collapsed pill, and every tool call with its diff in a
chat next to the code, a terminal and a live preview.

How to work:
- Finish the request with the fewest model rounds. Do not narrate a plan before
  acting, and do not run a command just to confirm something already visible.
- The project tree below is current. Skip list_files for simple edits. Read only
  the file you must change, then write it. Group independent tool calls in one
  reply.
- read_file is paged. When it says "Next offset", use that offset to continue.
  Never repeat a range you already received; if the needed code is in context,
  act on it.
- write_file replaces the whole file, so send complete contents. For an
  existing file, prefer edit_file with a unique old_text and the replacement
  new_text; this keeps large files inside the model's output budget.
- Finish the requested edit. Do not answer “Done” until edit_file or
  write_file has succeeded. If the request is already satisfied, state the
  evidence instead of claiming a change.
- Do not claim to have changed a file unless a file-writing tool succeeded.

Project files:
$files

Environment:
- ${fullShell ? 'run_command is the real device shell (/system/bin/sh) inside the project. The working directory is the project root. Use it for git, grep, archives, builds and any tool installed on the phone. Check `command -v name` first; Node, npm, Python and git are not bundled by Praxis.' : 'run_command is the file-ops shell; this test environment has no device binaries.'}
- Shell rules: run `cd` as its own command (the app tracks it for the next
  command); `cd x && command` stays inside that one command. Use POSIX tools
  such as `pwd`, `ls -la`, `cat`, `grep -R`, `find`, `wc`, `head`, `tail`, `sed`,
  `awk`, `tar`, `chmod` and `command -v`. A command succeeds only when the
  returned `exit` is 0; read the reported cwd and exit before continuing.
- `.praxis` is Praxis state. It always exists, is hidden from the file list, and
  is the correct place for skills (`.praxis/skills/<name>/SKILL.md`). Do not
  put project source there.
- Android app storage may mount files without execute permission. If a
  downloaded script gives “Permission denied” when run directly, invoke it as
  `sh path/to/script` instead. Do not assume `./tool` is executable.
- download_file preserves binary bytes and adds the active GitHub token for GitHub URLs.
- install_skill can read instructions you provide or fetch source_url from the web.
- ${onCommitAndPush != null ? 'commit_and_push commits and pushes when the user explicitly asks; it asks for destination confirmation first.' : 'Git push is not available in this run.'}
- ${onPullLatest != null ? 'pull_latest updates from the current GitHub branch after confirmation.' : 'Git pull is not available in this run.'}
- A web build is previewable when an index.html exists at the root, dist/, build/, build/web/ or out/.
- Binary assets are never decoded as text. Open them in Files to preview them.
- Secrets and API keys live in settings; never write them into project files.
${skillText.isEmpty ? '' : '\nSkills the user enabled:\n$skillText'}
''';
  }

  /// Project-installed skills use the Claude-style layout:
  /// `.praxis/skills/<name>/SKILL.md`. They are loaded for every prompt
  /// regardless of provider or model.
  Future<List<Skill>> _installedSkills() async {
    final installed = await ProjectSkillsStore.load(fs);
    return [
      for (final skill in installed)
        if (skill.instructions.isNotEmpty)
          Skill(
            id: 'project:${skill.slug}',
            name: skill.name,
            instructions: skill.instructions,
          ),
    ];
  }

  String _slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty
        ? 'skill-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        : slug;
  }

  String _yamlLine(String value) =>
      value.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();

  Future<String> _fileTree() async {
    try {
      final entries = await fs.list(includeHidden: true);
      if (entries.isEmpty) return '(empty project)';
      return entries
          .take(120)
          .map((entry) => entry.isDir
              ? '${entry.path}/'
              : '${entry.path} (${humanFileSize(entry.size)})')
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
          final entries = await fs.list(path: path, includeHidden: true);
          if (entries.isEmpty) return const _ToolOutcome('(empty)');
          return _ToolOutcome(entries
              .map((e) => e.isDir
                  ? '${e.path}/'
                  : '${e.path} (${humanFileSize(e.size)})')
              .join('\n'));
        case 'read_file':
          return await _readFile(call);
        case 'write_file':
          final path = (call.arguments['path'] as String? ?? '').trim();
          final content = call.arguments['content'] as String? ?? '';
          if (path.isEmpty) {
            return const _ToolOutcome('Error: path is required');
          }
          String before = '';
          try {
            before = await fs.exists(path) ? await fs.read(path) : '';
          } on FsError {
            before = '';
          }
          final bytes = await fs.write(path, content);
          final diff = computeDiff(before, content);
          _resetRepeat();
          return _ToolOutcome(
            'Wrote $bytes bytes to $path',
            diff: diff.isEmpty ? null : diff,
          );
        case 'edit_file':
          return await _editFile(call);
        case 'install_skill':
          return await _installSkill(call);
        case 'download_file':
          return await _downloadFile(call);
        case 'run_command':
          final command = (call.arguments['command'] as String? ?? '').trim();
          if (command.isEmpty) {
            return const _ToolOutcome('Error: command is required');
          }
          _resetRepeat();
          if (deviceShell != null) {
            final result = await deviceShell!.run(
              command,
              timeout: const Duration(seconds: 180),
            );
            final text = result.output.trim();
            final output = text.length > 12000
                ? '${text.substring(0, 12000)}\n… output truncated'
                : text;
            return _ToolOutcome(
              'cwd: ${result.cwd}\nexit: ${result.exitCode}\n'
              '${output.isEmpty ? '(no output)' : output}',
            );
          }
          final result = await shell.run(command);
          if (result.lines.isEmpty) return const _ToolOutcome('(no output)');
          final output = result.lines
              .map((line) => line.text)
              .where((line) => line.isNotEmpty)
              .join('\n');
          return _ToolOutcome(output.length > 12000
              ? '${output.substring(0, 12000)}\n… output truncated'
              : output);
        case 'commit_and_push':
          final action = onCommitAndPush;
          if (action == null) {
            return const _ToolOutcome('Error: GitHub push is not connected.');
          }
          final message = (call.arguments['message'] as String? ?? '').trim();
          if (message.isEmpty) {
            return const _ToolOutcome('Error: a commit message is required.');
          }
          _resetRepeat();
          return _ToolOutcome(await action(message));
        case 'pull_latest':
          final action = onPullLatest;
          if (action == null) {
            return const _ToolOutcome('Error: GitHub pull is not connected.');
          }
          _resetRepeat();
          return _ToolOutcome(await action());
        default:
          return _ToolOutcome('Error: unknown tool ${call.name}');
      }
    } on FsError catch (error) {
      return _ToolOutcome('Error: ${error.message}');
    } catch (error) {
      return _ToolOutcome('Error: $error');
    }
  }

  void _resetRepeat() {
    _lastCallSignature = null;
    _repeatedCalls = 0;
  }

  Future<_ToolOutcome> _editFile(AiToolCall call) async {
    final path = (call.arguments['path'] as String? ?? '').trim();
    final oldText = call.arguments['old_text'] as String? ?? '';
    final newText = call.arguments['new_text'] as String? ?? '';
    final replaceAll = call.arguments['replace_all'] as bool? ?? false;
    if (path.isEmpty) return const _ToolOutcome('Error: path is required');
    if (oldText.isEmpty) {
      return const _ToolOutcome('Error: old_text cannot be empty');
    }
    if (oldText == newText) {
      return const _ToolOutcome('Error: old_text and new_text are identical');
    }
    final before = await fs.read(path);
    final matches = RegExp(RegExp.escape(oldText)).allMatches(before).length;
    if (matches == 0) {
      return _ToolOutcome(
        'Error: old_text was not found in $path. Read the exact lines and try '
        'again with a unique snippet.',
      );
    }
    if (matches > 1 && !replaceAll) {
      return _ToolOutcome(
        'Error: old_text appears $matches times in $path. Add surrounding '
        'context or set replace_all to true.',
      );
    }
    final after = replaceAll
        ? before.replaceAll(oldText, newText)
        : before.replaceFirst(oldText, newText);
    await fs.write(path, after);
    final diff = computeDiff(before, after);
    _resetRepeat();
    return _ToolOutcome(
      'Edited $path ✓ ($matches replacement${matches == 1 ? '' : 's'}).',
      diff: diff.isEmpty ? null : diff,
    );
  }

  Future<_ToolOutcome> _readFile(AiToolCall call) async {
    final path = (call.arguments['path'] as String? ?? '').trim();
    if (path.isEmpty) return const _ToolOutcome('Error: path is required');
    final offset = _positiveInt(call.arguments['offset'], 1);
    final limit = _positiveInt(call.arguments['limit'], 350).clamp(1, 1200);
    final cacheKey = '$path\u0000$offset\u0000$limit';
    final content = await fs.read(path);
    final lines = content.split('\n');
    final total = lines.length;
    final start = offset - 1;
    if (start >= total) {
      return _ToolOutcome(
        'No lines at offset $offset: $path has $total lines. '
        'Do not read this file again at another offset unless you need a specific earlier range.',
      );
    }
    final selected = <String>[];
    var characters = 0;
    var end = start;
    while (end < total && selected.length < limit) {
      final line = lines[end];
      final nextLength = characters + line.length + (selected.isEmpty ? 0 : 1);
      if (selected.isNotEmpty && nextLength > 15000) break;
      selected.add(line);
      characters = nextLength;
      end++;
    }
    final nextOffset = end < total ? end + 1 : null;
    final repeats = (_readCache[cacheKey] ?? 0) + 1;
    _readCache[cacheKey] = repeats;
    final header = '[$path · lines ${start + 1}–$end of $total]';
    final footer = nextOffset == null
        ? 'End of file.'
        : 'Next offset: $nextOffset. Continue there only if you need more; do not repeat this range.';
    if (repeats > 1) {
      return _ToolOutcome(
        '$header\nThis exact range was already returned. Use the content in the '
        'conversation instead of reading it again.\n$footer',
      );
    }
    return _ToolOutcome('$header\n${selected.join('\n')}\n\n$footer');
  }

  int _positiveInt(Object? raw, int fallback) {
    final value = switch (raw) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v),
      _ => null,
    };
    if (value == null || value < 1) return fallback;
    return value;
  }

  Future<_ToolOutcome> _installSkill(AiToolCall call) async {
    var name = (call.arguments['name'] as String? ?? '').trim();
    var description = (call.arguments['description'] as String? ?? '').trim();
    var instructions = (call.arguments['instructions'] as String? ?? '').trim();
    final sourceUrl = (call.arguments['source_url'] as String? ?? '').trim();
    if (instructions.isEmpty && sourceUrl.isNotEmpty) {
      final fetch = fetchText;
      if (fetch == null) {
        return const _ToolOutcome(
            'Error: this session cannot download skill sources.');
      }
      final raw = await fetch(sourceUrl);
      final parsed = ProjectSkillsStore.parse(raw);
      if (name.isEmpty) name = parsed.name;
      if (description.isEmpty) description = parsed.description;
      instructions = parsed.body;
    }
    if (instructions.isEmpty) {
      return const _ToolOutcome(
          'Error: provide instructions or a source_url that contains a SKILL.md.');
    }
    if (name.isEmpty) {
      name = sourceUrl.isEmpty
          ? 'skill-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
          : sourceUrl
              .split('/')
              .where((part) => part.isNotEmpty)
              .last
              .replaceAll(
                  RegExp(r'\.(md|markdown)$', caseSensitive: false), '');
    }
    final slug = _slug(name);
    final path = '.praxis/skills/$slug/SKILL.md';
    final content = '---\n'
        'name: ${_yamlLine(name)}\n'
        'description: ${_yamlLine(description)}\n'
        '---\n\n'
        '$instructions\n';
    await fs.write(path, content);
    _resetRepeat();
    return _ToolOutcome(
      'Installed skill “$name” at $path. It is available to every future '
      'prompt for this project.',
    );
  }

  Future<_ToolOutcome> _downloadFile(AiToolCall call) async {
    final url = (call.arguments['url'] as String? ?? '').trim();
    final path = (call.arguments['path'] as String? ?? '').trim();
    if (url.isEmpty || path.isEmpty) {
      return const _ToolOutcome('Error: url and path are required');
    }
    final fetch = fetchBytes;
    if (fetch == null) {
      return const _ToolOutcome(
          'Error: downloads are unavailable in this session.');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return const _ToolOutcome(
          'Error: only http and https URLs are supported.');
    }
    final bytes = await fetch(url);
    await fs.writeBytes(path, bytes);
    _resetRepeat();
    return _ToolOutcome(
      'Downloaded ${humanFileSize(bytes.length)} to $path.',
    );
  }

  String _detail(AiToolCall call) {
    final args = call.arguments;
    switch (call.name) {
      case 'write_file':
      case 'edit_file':
      case 'read_file':
        return '${args['path'] ?? '?'}';
      case 'run_command':
        return '${args['command'] ?? '?'}';
      case 'install_skill':
        return '${args['name'] ?? args['source_url'] ?? 'skill'}';
      case 'download_file':
        return '${args['path'] ?? args['url'] ?? '?'}';
      case 'commit_and_push':
        return '${args['message'] ?? 'commit'}';
      case 'pull_latest':
        return 'latest commit';
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
