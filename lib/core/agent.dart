import 'dart:convert';

import '../models.dart';
import 'ai.dart';
import 'context_prefetch.dart';
import 'diff.dart';
import 'file_types.dart';
import 'patch.dart';
import 'phase1_flags.dart';
import 'project_skills.dart';
import 'round_log.dart';
import 'sensitive_paths.dart';
import 'shell.dart';
import 'task_checkpoint.dart';
import 'system_shell.dart';
import 'tool_validation.dart';
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

/// Asks the user before a compound action runs. The body must list every
/// command the call will perform, not just the tool name.
typedef AgentToolApproval = Future<bool> Function(
  String title,
  String body,
  String confirmLabel,
);

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

const _compoundTools = <AiToolSpec>[
  AiToolSpec(
    name: 'read_files',
    description:
        'Read several files in one call. Use this instead of issuing one '
        'read_file call per file. Every result names its line range and gives '
        'the exact next offset when more lines exist; large reads are capped and '
        'never silently clipped.',
    parameters: {
      'type': 'object',
      'properties': {
        'paths': {
          'type': 'array',
          'description':
              'Up to 8 paths. Each item is a path string or an object with path, '
                  'optional offset and optional limit.',
          'items': {},
        },
      },
      'required': ['paths'],
    },
  ),
  AiToolSpec(
    name: 'search_and_read',
    description:
        'Search project text and return matching snippets with surrounding '
        'lines in one call. Use this instead of grep followed by read_file.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Text to search for.'},
        'glob': {
          'type': 'string',
          'description': 'Optional path glob, for example lib/**/*.dart.',
        },
        'maxFiles': {
          'type': 'integer',
          'description': 'Maximum files to inspect, 1–40. Defaults to 12.',
        },
      },
      'required': ['query'],
    },
  ),
  AiToolSpec(
    name: 'run_commands',
    description:
        'Run several shell commands sequentially in one call. Stops at the '
        'first non-zero exit and returns every result. The user sees the full '
        'command list for approval before anything runs.',
    parameters: {
      'type': 'object',
      'properties': {
        'commands': {
          'type': 'array',
          'description': '1–8 command lines to run in order.',
          'items': {'type': 'string'},
        },
      },
      'required': ['commands'],
    },
  ),
  AiToolSpec(
    name: 'apply_patch',
    description:
        'Apply a compact *** Begin Patch block or a unified diff to one or more '
        'files in a single edit. Use this for multi-file changes.',
    parameters: {
      'type': 'object',
      'properties': {
        'patch': {
          'type': 'string',
          'description': 'The complete patch text.',
        },
      },
      'required': ['patch'],
    },
  ),
];

bool providerSupportsParallelToolCalls(ProviderConfig provider) {
  const supported = {
    'openai',
    'anthropic',
    'openrouter',
    'gemini',
    'groq',
    'deepseek',
    'mistral',
    'cerebras',
    'together',
    'nvidia',
  };
  return supported.contains(provider.id);
}

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
    this.onModelRequest,
    this.skipActionFingerprints = const {},
    this.onTextDelta,
    this.onThinkingDelta,
    this.onToolStart,
    this.onReply,
    this.onDiscardLive,
    this.roundLog,
    this.taskId,
    this.flags = Phase1Flags.defaults,
    this.activeFile,
    this.linuxShell = false,
    this.toolApproval,
    this.repeatLimit = Phase1Flags.repeatLimit,
    this.maxRounds = 40,
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
  final void Function(ProviderConfig provider)? onModelRequest;

  /// Exact actions that finished before a checkpoint. Matching calls are
  /// acknowledged but never executed a second time.
  final Set<String> skipActionFingerprints;
  final void Function(String delta)? onTextDelta;
  final void Function(String delta)? onThinkingDelta;
  final void Function(AiToolCall call)? onToolStart;
  final void Function(AiReply reply, ProviderConfig provider)? onReply;

  /// Clears streamed text when the agent has to retry a completion that made
  /// no file change. Without this, a premature "Done" would stay in the live
  /// reply above the corrective round.
  final void Function()? onDiscardLive;

  /// Phase 0 instrumentation. Null disables logging; no behavior depends on it.
  final RoundLogStore? roundLog;
  final String? taskId;
  final Phase1Flags flags;
  final String? activeFile;
  final bool linuxShell;
  final AgentToolApproval? toolApproval;
  final int repeatLimit;
  final int maxRounds;

  final Map<String, int> _readCache = {};
  final Map<String, int> _signatureCounts = {};
  final Map<String, int> _argumentFailureCounts = {};
  final Map<String, int> _editFailureCounts = {};
  String? _verificationCommand;

  List<AiToolSpec> get _tools => [
        ..._baseAgentTools,
        if (flags.compoundTools) ..._compoundTools,
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
    final prefetched = flags.contextPrefetch
        ? await ContextPrefetch(
            fs: fs,
            shell: deviceShell,
            activeFile: activeFile,
          ).build(prompt)
        : null;
    final initialPrompt = prefetched?.included == true
        ? '${prefetched!.text}\n\nUSER REQUEST\n$prompt'
        : prompt;
    final turns = <AiTurn>[...history, AiTurn.user(initialPrompt)];
    if (flags.compoundTools) await _detectVerificationCommand();
    var current = provider;
    var mutated = false;
    var completionNudges = 0;
    var limitNudges = 0;
    final log = roundLog;
    final task = taskId ?? 'task-${DateTime.now().microsecondsSinceEpoch}';
    final seenCalls = <String>{};
    var requestIndex = 0;
    var previousToolFailed = false;
    var outcome = AgentOutcome.error;

    try {
      for (var round = 0; round < maxRounds; round++) {
        if (isCancelled?.call() ?? false) {
          outcome = AgentOutcome.userCancelled;
          return;
        }

        AiReply reply;
        var switches = 0;
        while (true) {
          final requestedAt = DateTime.now();
          final thisRound = requestIndex++;
          final requestProvider = current;
          onModelRequest?.call(current);
          try {
            reply = await client.stream(
              provider: current,
              system: system,
              turns: turns,
              tools: _tools,
              maxTokens: kDefaultMaxOutputTokens,
              onText: onTextDelta,
              onThinking: onThinkingDelta,
              isCancelled: isCancelled,
            );
          } on AiCancelledException {
            outcome = AgentOutcome.userCancelled;
            return;
          } on AiProviderException catch (error) {
            // A failed attempt is still a model request. Record its provider
            // and timestamp without arguments or prompt text.
            await _recordRound(
              log,
              AgentRound(
                taskId: task,
                roundIndex: thisRound,
                at: requestedAt,
                provider: requestProvider.id,
                model: requestProvider.model,
                toolNames: const [],
                type: RoundType.other,
                repeatedCall: false,
                finishReason: 'error',
              ),
            );
            final handler = onProviderLimit;
            if (!error.isLimit || handler == null || switches >= 3) {
              outcome =
                  error.isLimit ? AgentOutcome.quotaError : AgentOutcome.error;
              rethrow;
            }
            final next = await handler(current, error);
            if (next == null) {
              outcome =
                  error.isLimit ? AgentOutcome.quotaError : AgentOutcome.error;
              rethrow;
            }
            if (next.id != current.id &&
                !providerSupportsParallelToolCalls(next)) {
              turns.add(const AiTurn.user(
                'Capability update: the new provider does not support parallel '
                'read calls. Do not batch tool calls; request one at a time.',
              ));
            }
            current = next;
            switches++;
            continue;
          }
          onReply?.call(reply, current);

          final signatures = reply.calls
              .map((call) => '${call.name}:${jsonEncode(call.arguments)}')
              .toList();
          final repeatedCall = signatures.any(seenCalls.contains);
          seenCalls.addAll(signatures);
          await _recordRound(
            log,
            AgentRound(
              taskId: task,
              roundIndex: thisRound,
              at: requestedAt,
              provider: current.id,
              model: current.model,
              inputTokens: reply.usage?.promptTokens,
              outputTokens: reply.usage?.completionTokens,
              toolNames: reply.calls.map((call) => call.name).toList(),
              type: classifyRound(
                reply.calls,
                previousToolFailed: previousToolFailed,
              ),
              repeatedCall: repeatedCall,
              finishReason: reply.finishReason,
            ),
          );
          break;
        }

        if (reply.calls.isEmpty) {
          final text = reply.text.trim();
          final wantsChange = _looksLikeChangeRequest(prompt);

          // A reasoning model can spend the entire output budget before it emits
          // its tool call. That is not a completed answer, so never print the
          // old "Done — no changes were needed" placeholder for it.
          if (reply.hitOutputLimit && limitNudges < 2) {
            limitNudges++;
            onDiscardLive?.call();
            if (text.isNotEmpty) {
              turns.add(AiTurn.assistant(reply.text, const []));
            }
            turns.add(const AiTurn.user(
              'Your previous response was cut off by the model output limit '
              'before you acted. Continue from the work already done. Do not '
              'repeat the plan or keep reasoning: use edit_file for the existing '
              'file or write_file for a new file now. Keep the tool call compact.',
            ));
            continue;
          }

          if (!reply.hitOutputLimit &&
              !mutated &&
              completionNudges < 2 &&
              wantsChange) {
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

          if (!mutated && wantsChange) {
            outcome = AgentOutcome.error;
            onEvent(AgentEvent.error(
              text.isEmpty
                  ? 'The model stopped without changing a file and returned no '
                      'text. This is usually an output-budget or tool-call '
                      'failure; send “continue” to retry.'
                  : 'The model stopped without changing a file. It said: “$text”\n'
                      'Send “continue” to retry the edit.',
            ));
            return;
          }

          if (text.isEmpty) {
            outcome = AgentOutcome.error;
            onEvent(const AgentEvent.error(
              'The model returned an empty reply. Send “continue” to retry.',
            ));
            return;
          }
          outcome = AgentOutcome.completed;
          onEvent(AgentEvent.text(text, thinking: reply.thinking));
          return;
        }
        turns.add(AiTurn.assistant(reply.text, reply.calls));
        if (reply.text.trim().isNotEmpty || reply.thinking.trim().isNotEmpty) {
          onEvent(AgentEvent.text(
            reply.text.trim(),
            thinking: reply.thinking.trim(),
          ));
        }
        final calls = reply.calls;
        final validations = <String?>[
          for (final call in calls)
            flags.loopGuards ? validateToolArguments(call, _tools) : null,
        ];
        var schemaStop = false;
        for (var index = 0; index < calls.length; index++) {
          final validation = validations[index];
          if (validation == null) continue;
          final key = '${calls[index].name}:$validation';
          final count = (_argumentFailureCounts[key] ?? 0) + 1;
          _argumentFailureCounts[key] = count;
          if (flags.loopGuards && count >= repeatLimit) schemaStop = true;
        }
        if (schemaStop) {
          outcome = AgentOutcome.loopDetected;
          onEvent(const AgentEvent.error(
            'Stopped: the model kept sending tool arguments that do not match '
            'the schema. The error above names the expected shape. Send '
            '“continue” to retry with a different approach.',
          ));
          return;
        }

        var repeatedStop = false;
        for (final call in calls) {
          final signature = '${call.name}:${jsonEncode(call.arguments)}';
          final count = (_signatureCounts[signature] ?? 0) + 1;
          _signatureCounts[signature] = count;
          if (flags.loopGuards && count >= repeatLimit) repeatedStop = true;
        }
        if (repeatedStop) {
          outcome = AgentOutcome.loopDetected;
          onEvent(AgentEvent.error(
            'Stopped: the model repeated the same ${calls.last.name} call '
            '$repeatLimit times with identical arguments. This usually means '
            'the edit or read did not give it the result it expected. Send '
            '“continue” to retry with a different approach.',
          ));
          return;
        }

        final canRunReadsInParallel = flags.batchedExecution &&
            calls.length > 1 &&
            providerSupportsParallelToolCalls(current) &&
            calls.every(
                (call) => Phase1Flags.readOnlyTools.contains(call.name)) &&
            validations.every((validation) => validation == null);
        for (final call in calls) {
          if (isCancelled?.call() ?? false) {
            outcome = AgentOutcome.userCancelled;
            return;
          }
          onToolStart?.call(call);
        }

        final results = List<_ToolOutcome?>.filled(calls.length, null);
        if (canRunReadsInParallel) {
          final futures = <Future<_ToolOutcome>>[];
          for (var index = 0; index < calls.length; index++) {
            futures
                .add(_executeAfterValidation(calls[index], validations[index]));
          }
          final completed = await Future.wait(futures);
          for (var index = 0; index < completed.length; index++) {
            results[index] = completed[index];
          }
        } else {
          for (var index = 0; index < calls.length; index++) {
            final result =
                await _executeAfterValidation(calls[index], validations[index]);
            results[index] = result;
            if (result.failed && calls[index].name != 'run_commands') break;
          }
        }

        var roundFailed = false;
        for (var index = 0; index < calls.length; index++) {
          final call = calls[index];
          final result = results[index];
          if (result == null) {
            // A later command was intentionally skipped after the previous
            // command failed. Do not invent a result or retry a write.
            turns.add(AiTurn.tool(
              call.id,
              call.name,
              'Skipped because an earlier command in this round failed.',
            ));
            continue;
          }
          if (result.failed) roundFailed = true;
          if (!mutated &&
              const {
                'write_file',
                'edit_file',
                'apply_patch',
                'download_file',
                'install_skill',
              }.contains(call.name) &&
              !result.text.startsWith('Error')) {
            mutated = true;
          }
          if (flags.loopGuards &&
              result.failed &&
              const {'edit_file', 'write_file', 'apply_patch'}
                  .contains(call.name)) {
            final key = '${call.name}:${jsonEncode(call.arguments)}';
            final count = (_editFailureCounts[key] ?? 0) + 1;
            _editFailureCounts[key] = count;
            if (count >= repeatLimit) {
              outcome = AgentOutcome.loopDetected;
              onEvent(AgentEvent.error(
                'Stopped: the same ${call.name} failed $count times in a row. '
                'Re-read the file or use a different edit. Send “continue” to '
                'resume with a different approach.',
              ));
              return;
            }
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
        previousToolFailed = roundFailed;
      }
      outcome = AgentOutcome.loopDetected;
      onEvent(AgentEvent.error(
        'Paused after $maxRounds tool rounds. Send “continue” to keep going.',
      ));
    } on AiCancelledException {
      outcome = AgentOutcome.userCancelled;
      return;
    } on AiProviderException catch (error) {
      outcome = error.isLimit ? AgentOutcome.quotaError : AgentOutcome.error;
      rethrow;
    } catch (_) {
      outcome = AgentOutcome.error;
      rethrow;
    } finally {
      await _finishTask(log, task, outcome);
    }
  }

  Future<void> _recordRound(RoundLogStore? log, AgentRound round) async {
    if (log == null) return;
    try {
      await log.appendRound(round);
    } catch (_) {
      // Instrumentation must never break a model run.
    }
  }

  Future<void> _finishTask(
    RoundLogStore? log,
    String taskId,
    AgentOutcome outcome,
  ) async {
    if (log == null) return;
    try {
      await log.finishTask(taskId, outcome);
    } catch (_) {
      // Instrumentation must never break a model run.
    }
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
    final parallelTools = providerSupportsParallelToolCalls(provider);
    return '''
You are Praxis, an AI coding agent running on the user's Android phone.
You work on a real project folder on the device. The user sees your replies,
your reasoning behind a collapsed pill, and every tool call with its diff in a
chat next to the code, a terminal and a live preview.

How to work:
- Finish the request with the fewest model rounds. Do not narrate a plan before
  acting, and do not run a command just to confirm something already visible.
- Keep reasoning short. Once you know the edit, call edit_file or write_file;
  a long internal monologue can consume the output budget before you act.
- The project tree below is current. Skip list_files for simple edits. Read only
  the file you must change, then write it.
${parallelTools ? '- Batch independent reads and searches in one response so their results land together. Never batch a write with a read that depends on it.' : ''}
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
- ${linuxShell ? 'The shell is a real Alpine Linux 3.21 environment running under proot. Use `apk add`, `apk del`, `apk update` and Alpine paths. `apt`, `apt-get` and Debian package names do not exist here. The project is bind-mounted at /workspace. Node, Python, PHP and Go are installed on demand from the Linux Environment screen; check `command -v name` first.' : fullShell ? 'run_command is the real device shell (/system/bin/sh) inside the project. The working directory is the project root. Use it for git, grep, archives, builds and any tool installed on the phone. Check `command -v name` first; Node, npm, Python and git are not bundled by Praxis.' : 'run_command is the file-ops shell; this test environment has no device binaries.'}
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
      final entries = (await fs.list(includeHidden: true))
          .where((entry) =>
              !isIgnoredPath(entry.path) && !looksLikeSecret(entry.path))
          .toList();
      if (entries.isEmpty) return '(empty project)';
      final shown = entries.take(120).map((entry) => entry.isDir
          ? '${entry.path}/'
          : '${entry.path} (${humanFileSize(entry.size)})');
      final omitted = entries.length > 120
          ? '\n[${entries.length - 120} more entries omitted; call list_files '
              'for a specific directory.]'
          : '';
      return '${shown.join('\n')}$omitted';
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
          final lines = entries
              .map((e) => e.isDir
                  ? '${e.path}/'
                  : '${e.path} (${humanFileSize(e.size)})')
              .toList();
          if (!flags.resultSizing || lines.length <= 300) {
            return _ToolOutcome(lines.join('\n'));
          }
          return _ToolOutcome(
            '${lines.take(300).join('\n')}\n\n'
            '[${lines.length - 300} more entries omitted. Call list_files for '
            'a specific directory to see the rest.]',
          );
        case 'read_file':
          return await _readFile(call);
        case 'read_files':
          return await _readFiles(call);
        case 'search_and_read':
          return await _searchAndRead(call);
        case 'apply_patch':
          final patchText = call.arguments['patch'] as String? ?? '';
          final approval = toolApproval;
          if (approval != null) {
            final allowed = await approval(
              'Apply this patch?',
              _patchSummary(patchText),
              'Apply patch',
            );
            if (!allowed) {
              return const _ToolOutcome('Patch cancelled by the user.');
            }
          }
          final applied = await applyPatch(fs, patchText);
          return _ToolOutcome(
            '${applied.summary}${await _verificationSuffix()}',
          );
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
          return _ToolOutcome(
            'Wrote $bytes bytes to $path${await _verificationSuffix()}',
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
          return _runSingleCommand(command);
        case 'run_commands':
          return await _runCommands(call);
        case 'commit_and_push':
          final action = onCommitAndPush;
          if (action == null) {
            return const _ToolOutcome('Error: GitHub push is not connected.');
          }
          final message = (call.arguments['message'] as String? ?? '').trim();
          if (message.isEmpty) {
            return const _ToolOutcome('Error: a commit message is required.');
          }
          return _ToolOutcome(await action(message));
        case 'pull_latest':
          final action = onPullLatest;
          if (action == null) {
            return const _ToolOutcome('Error: GitHub pull is not connected.');
          }
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

  String _patchSummary(String patch) {
    final paths = <String>[];
    for (final line in patch.split('\n')) {
      for (final prefix in const [
        '*** Update File: ',
        '*** Add File: ',
        '*** Delete File: ',
        '+++ ',
      ]) {
        if (line.startsWith(prefix)) {
          final path = line.substring(prefix.length).trim();
          if (path.isNotEmpty && !paths.contains(path)) {
            paths.add(path);
          }
        }
      }
    }
    if (paths.isEmpty) {
      return 'The patch does not name a file. It will fail before writing.';
    }
    return 'This patch will change:\n${paths.map((path) => '- $path').join('\n')}';
  }

  static const _checkpointGuardedTools = {
    'write_file',
    'edit_file',
    'apply_patch',
    'download_file',
    'install_skill',
    'run_command',
    'run_commands',
    'commit_and_push',
    'pull_latest',
  };

  Future<_ToolOutcome> _executeAfterValidation(
    AiToolCall call,
    String? validation,
  ) async {
    if (validation != null) return _ToolOutcome('Error: $validation');
    if (_checkpointGuardedTools.contains(call.name)) {
      final fingerprint =
          TaskCheckpoint.actionFingerprint(call.name, call.arguments);
      if (skipActionFingerprints.contains(fingerprint)) {
        return const _ToolOutcome(
          'Already completed at the checkpoint. Skipped to avoid a duplicate '
          'write or destructive action.',
        );
      }
    }
    return _execute(call);
  }

  Future<_ToolOutcome> _runSingleCommand(String command) async {
    if (deviceShell != null) {
      final result = await deviceShell!.run(
        command,
        timeout: const Duration(seconds: 180),
      );
      final text = result.output.trim();
      final output = _boundedOutput(text);
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
    return _ToolOutcome(_boundedOutput(output));
  }

  String _boundedOutput(String text) {
    if (!flags.resultSizing || text.length <= 12000) return text;
    final shown = text.substring(0, 12000);
    return '$shown\n\n[${text.length - 12000} more characters omitted. '
        'Re-run a narrower command to see the rest.]';
  }

  Future<_ToolOutcome> _runCommands(AiToolCall call) async {
    final raw = call.arguments['commands'];
    if (raw is! List) {
      return const _ToolOutcome('Error: commands must be an array.');
    }
    final commands = raw
        .whereType<String>()
        .map((command) => command.trim())
        .where((command) => command.isNotEmpty)
        .toList();
    if (commands.isEmpty) {
      return const _ToolOutcome('Error: at least one command is required.');
    }
    if (commands.length > 8) {
      return const _ToolOutcome('Error: at most 8 commands can run at once.');
    }
    final approval = toolApproval;
    if (approval != null) {
      final allowed = await approval(
        'Run ${commands.length} command${commands.length == 1 ? '' : 's'}?',
        commands
            .asMap()
            .entries
            .map((entry) => '${entry.key + 1}. ${entry.value}')
            .join('\n'),
        'Run commands',
      );
      if (!allowed) {
        return const _ToolOutcome('Command batch cancelled by the user.');
      }
    }
    final output = StringBuffer();
    var stopped = false;
    for (var index = 0; index < commands.length; index++) {
      final command = commands[index];
      output.writeln('$index. \$ $command');
      final result = await _runSingleCommand(command);
      output.writeln(result.text);
      if (result.failed) {
        stopped = true;
        break;
      }
    }
    if (stopped) {
      output.writeln('Stopped after the first failing command.');
    }
    return _ToolOutcome(output.toString().trim());
  }

  Future<_ToolOutcome> _readFiles(AiToolCall call) async {
    final raw = call.arguments['paths'];
    if (raw is! List) {
      return const _ToolOutcome('Error: paths must be an array.');
    }
    if (raw.length > 8) {
      return const _ToolOutcome(
        'Error: read_files accepts at most 8 files per call. Split the list.',
      );
    }
    final output = StringBuffer();
    var total = 0;
    var omitted = 0;
    for (var index = 0; index < raw.length; index++) {
      String path;
      int offset = 1;
      int limit = 350;
      final item = raw[index];
      if (item is String) {
        path = item.trim();
      } else if (item is Map) {
        path = (item['path'] as String? ?? '').trim();
        offset = _positiveInt(item['offset'], 1);
        limit = _positiveInt(item['limit'], 350).clamp(1, 1200);
      } else {
        output.writeln('Error: paths[$index] must be a path string or object.');
        continue;
      }
      if (path.isEmpty) {
        output.writeln('Error: paths[$index] is empty.');
        continue;
      }
      if (isIgnoredPath(path)) {
        output.writeln('$path: excluded from model context.');
        omitted++;
        continue;
      }
      try {
        final content = await fs.read(path);
        final lines = content.split('\n');
        final start = (offset - 1).clamp(0, lines.length);
        final selected = <String>[];
        var chars = 0;
        var end = start;
        while (end < lines.length && selected.length < limit) {
          final next = chars + lines[end].length + 1;
          if (selected.isNotEmpty && next > 12000) break;
          selected.add(lines[end]);
          chars = next;
          end++;
        }
        final header = '[$path · lines ${start + 1}–$end of ${lines.length}]';
        final footer = end < lines.length
            ? 'Next offset: ${end + 1}. Continue only if you need the rest.'
            : 'End of file.';
        final block = '$header\n${selected.join('\n')}\n\n$footer';
        if (total + block.length > 36000) {
          omitted++;
          output.writeln(
            '$path: omitted because the 36K read_files cap was reached. '
            'Call read_file with offset=$offset to read it separately.',
          );
          continue;
        }
        total += block.length;
        output.writeln(block);
      } on FsError catch (error) {
        output.writeln('$path: ${error.message}');
      }
    }
    if (omitted > 0) {
      output.writeln(
        '[$omitted file${omitted == 1 ? '' : 's'} omitted. Use read_file with '
        'an offset to inspect the rest.]',
      );
    }
    return _ToolOutcome(output.toString().trim());
  }

  Future<_ToolOutcome> _searchAndRead(AiToolCall call) async {
    final query = (call.arguments['query'] as String? ?? '').trim();
    final glob = (call.arguments['glob'] as String? ?? '').trim();
    final maxFiles = _positiveInt(call.arguments['maxFiles'], 12).clamp(1, 40);
    if (query.length < 2) {
      return const _ToolOutcome('Error: query must be at least 2 characters.');
    }
    final matcher = _globRegExp(glob);
    final output = StringBuffer();
    var files = 0;
    var hits = 0;
    var total = 0;
    List<FileEntry> entries;
    try {
      entries = await fs.list(includeHidden: true);
    } on FsError catch (error) {
      return _ToolOutcome('Error: ${error.message}');
    }
    for (final entry in entries) {
      if (entry.isDir || entry.size > 150000) continue;
      if (isIgnoredPath(entry.path) || looksLikeSecret(entry.path)) continue;
      if (matcher != null && !matcher.hasMatch(entry.path)) continue;
      String text;
      try {
        if (!await fs.isTextFile(entry.path)) continue;
        text = await fs.read(entry.path);
      } on FsError {
        continue;
      }
      final lines = text.split('\n');
      final lower = query.toLowerCase();
      final fileHits = <int>[];
      for (var index = 0; index < lines.length; index++) {
        if (lines[index].toLowerCase().contains(lower)) fileHits.add(index);
      }
      if (fileHits.isEmpty) continue;
      files++;
      output.writeln('\n${entry.path}');
      for (final line in fileHits.take(4)) {
        hits++;
        final start = (line - 2).clamp(0, lines.length - 1);
        final end = (line + 2).clamp(0, lines.length - 1);
        for (var context = start; context <= end; context++) {
          final marker = context == line ? '>' : ' ';
          final value = lines[context].length > 240
              ? '${lines[context].substring(0, 240)}…'
              : lines[context];
          final row = '$marker ${context + 1} | $value\n';
          if (total + row.length > 24000) {
            output.writeln(
              '[search output capped at 24K characters; refine the query or '
              'use read_file for the rest.]',
            );
            return _ToolOutcome(output.toString().trim());
          }
          total += row.length;
          output.write(row);
        }
      }
      if (files >= maxFiles || hits >= 40) break;
    }
    if (hits == 0) {
      return _ToolOutcome(
          'No matches for “$query” ${glob.isEmpty ? '' : 'in $glob '}.');
    }
    final suffix = files >= maxFiles || hits >= 40
        ? '\n[Showing the first $files files and $hits hits; narrow the query to see more.]'
        : '';
    return _ToolOutcome('${output.toString().trim()}$suffix');
  }

  RegExp? _globRegExp(String glob) {
    if (glob.isEmpty) return null;
    final buffer = StringBuffer('^');
    for (var index = 0; index < glob.length; index++) {
      final char = glob[index];
      if (char == '*') {
        if (index + 1 < glob.length && glob[index + 1] == '*') {
          buffer.write('.*');
          index++;
        } else {
          buffer.write('[^/]*');
        }
      } else if (char == '?') {
        buffer.write('[^/]');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  Future<void> _detectVerificationCommand() async {
    if (_verificationCommand != null) return;
    try {
      if (await fs.exists('pubspec.yaml')) {
        _verificationCommand = 'flutter analyze';
        return;
      }
      if (await fs.exists('package.json')) {
        final data = jsonDecode(await fs.read('package.json'));
        final scripts = data is Map ? data['scripts'] : null;
        if (scripts is Map) {
          if (scripts['typecheck'] is String) {
            _verificationCommand = 'npm run typecheck';
            return;
          }
          if (scripts['lint'] is String) {
            _verificationCommand = 'npm run lint';
            return;
          }
        }
      }
      if (await fs.exists('Cargo.toml')) {
        _verificationCommand = 'cargo check';
        return;
      }
      if (await fs.exists('go.mod')) {
        _verificationCommand = 'go vet ./...';
        return;
      }
      if (await fs.exists('pyproject.toml')) {
        final config = await fs.read('pyproject.toml');
        if (config.contains('[tool.ruff')) {
          _verificationCommand = 'python -m ruff check .';
        }
      }
    } catch (_) {
      _verificationCommand = null;
    }
  }

  Future<String> _verificationSuffix() async {
    if (!flags.compoundTools) return '';
    final command = _verificationCommand;
    if (command == null || deviceShell == null) return '';
    try {
      final result = await deviceShell!.run(
        command,
        timeout: const Duration(seconds: 120),
      );
      final output = _boundedOutput(result.output.trim());
      final status = result.exitCode == 0 ? 'passed' : 'failed';
      return '\n\nVerification ($command) $status (exit ${result.exitCode}).'
          '${output.isEmpty ? '' : '\n$output'}';
    } catch (_) {
      return '';
    }
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
    return _ToolOutcome(
      'Edited $path ✓ ($matches replacement${matches == 1 ? '' : 's'}).'
      '${await _verificationSuffix()}',
      diff: diff.isEmpty ? null : diff,
    );
  }

  Future<_ToolOutcome> _readFile(AiToolCall call) async {
    final path = (call.arguments['path'] as String? ?? '').trim();
    if (path.isEmpty) return const _ToolOutcome('Error: path is required');
    if (isIgnoredPath(path) || looksLikeSecret(path)) {
      return _ToolOutcome(
        'Error: $path is excluded from model context because it can contain '
        'secrets or generated output. Read a source file instead.',
      );
    }
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
      case 'apply_patch':
        return 'patch';
      case 'read_files':
        final paths = args['paths'];
        if (paths is List) return '${paths.length} files';
        return 'files';
      case 'search_and_read':
        return '${args['query'] ?? '?'}';
      case 'run_commands':
        final commands = args['commands'];
        if (commands is List) return '${commands.length} commands';
        return 'commands';
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

  /// Used only to classify the next round as a retry. The text is never parsed
  /// for logging; it is already the agent's sanitized tool result.
  bool get failed =>
      text.startsWith('Error') ||
      RegExp(r'(^|\n)exit: [1-9]\d*').hasMatch(text);
}
