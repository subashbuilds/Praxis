import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/agent_todos.dart';
import '../core/diff.dart';
import '../core/follow_ups.dart';
import '../core/task_checkpoint.dart';
import '../core/undo_store.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/chat_markdown.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/ui.dart';

/// Styles slash skills and @file tags inside the composer itself, so a command
/// stays visible after it is typed and not only while the suggestion panel is
/// open.
class _PromptController extends TextEditingController {
  static final _token = RegExp(r'(^|\s)([/@][A-Za-z0-9._/-]+)');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in _token.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      final prefix = match.group(1) ?? '';
      if (prefix.isNotEmpty) spans.add(TextSpan(text: prefix));
      final token = match.group(2) ?? '';
      spans.add(TextSpan(
        text: token,
        style: base.copyWith(
          color: Pal.ember,
          fontWeight: FontWeight.w600,
        ),
      ));
      index = match.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return TextSpan(style: base, children: spans);
  }
}

class AgentTab extends StatefulWidget {
  const AgentTab({super.key, required this.project});

  final Project project;

  @override
  State<AgentTab> createState() => _AgentTabState();
}

class _AgentTabState extends State<AgentTab> {
  final _composer = _PromptController();
  final _scroll = ScrollController();
  final _attachments = <String>[];
  int _lastThreadLength = 0;
  int _lastLiveSignal = 0;
  bool _stickToBottom = true;
  bool _showJumpToBottom = false;
  final _openThinking = <String>{};
  bool _liveThinkingOpen = false;
  bool _draftRestored = false;
  bool _todosLoaded = false;
  bool _loadingFollowUps = false;
  UndoTask? _undoTask;
  bool _undoLoaded = false;
  bool _undoBusy = false;
  bool _lastBusy = false;
  AppState? _state;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    _state = state;
    if (!_draftRestored) {
      _draftRestored = true;
      final draft = state.promptDraftFor(widget.project.id);
      _composer.text = draft;
      _composer.selection = TextSelection.collapsed(offset: draft.length);
      _composer.addListener(_persistDraft);
    }
    if (!_todosLoaded) {
      _todosLoaded = true;
      unawaited(state.loadTodos(widget.project));
    }
    if (!_undoLoaded) {
      _undoLoaded = true;
      unawaited(_loadUndo());
    }
  }

  Future<void> _loadUndo() async {
    final state = _state;
    if (state == null) return;
    try {
      final task = await state.undoableTask(widget.project);
      if (!mounted) return;
      setState(() => _undoTask = task);
    } catch (_) {
      if (mounted) setState(() => _undoTask = null);
    }
  }

  Future<void> _undoLastTask() async {
    final state = _state;
    final task = _undoTask;
    if (state == null || task == null || _undoBusy) return;
    final count = task.fileCount;
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Undo the last task?',
      body: 'Every file that task changed goes back to how it was before it '
          'started. Files changed by shell commands are not part of this.',
      confirmLabel: 'Undo task',
      destructive: true,
      icon: Icons.undo_rounded,
      details: [
        ConfirmDetail('Files', '$count'),
        if (task.label.isNotEmpty) ConfirmDetail('Task', task.label),
      ],
    );
    if (!confirmed || !mounted) return;
    setState(() => _undoBusy = true);
    try {
      final message = await state.undoLastTask(widget.project);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not undo: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _undoBusy = false);
        unawaited(_loadUndo());
      }
    }
  }

  @override
  void dispose() {
    _state?.setPromptDraft(widget.project.id, _composer.text);
    _composer.removeListener(_persistDraft);
    _composer.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _persistDraft() {
    _state?.setPromptDraft(widget.project.id, _composer.text);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // The transcript list is reversed, so the newest entry sits at offset 0.
    final nearBottom = _scroll.position.pixels <= 80;
    if (nearBottom == _stickToBottom) return;
    setState(() {
      _stickToBottom = nearBottom;
      _showJumpToBottom = !nearBottom;
    });
  }

  void _scrollToEnd({bool force = false}) {
    if (!force && !_stickToBottom) return;
    if (force && !_stickToBottom) {
      setState(() {
        _stickToBottom = true;
        _showJumpToBottom = false;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(0);
    });
  }

  Future<void> _pickAttachments() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Pal.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            ListTile(
              leading: Icon(Icons.image_outlined, color: Pal.textMuted),
              title: const Text('Photos'),
              subtitle: const Text('Images from the gallery'),
              onTap: () => Navigator.of(sheetContext).pop('image'),
            ),
            ListTile(
              leading: Icon(Icons.attach_file_rounded, color: Pal.textMuted),
              title: const Text('Any file'),
              subtitle: const Text('Text, PDF or zip, copied into the project'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: kind == 'image' ? FileType.image : FileType.any,
        allowMultiple: true,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the picker: $error')),
      );
      return;
    }
    if (!mounted) return;
    final paths = result?.files
            .map((file) => file.path)
            .whereType<String>()
            .where((path) => path.isNotEmpty)
            .toList() ??
        const <String>[];
    if (paths.isEmpty) return;
    setState(() => _attachments.addAll(paths));
  }

  bool _hasCompletedRun(List<ChatEntry> thread) {
    var found = false;
    for (var index = thread.length - 1; index >= 0; index--) {
      final entry = thread[index];
      if (entry.role == ChatRole.user) return false;
      if (entry.role == ChatRole.assistant && entry.text.trim().isNotEmpty) {
        found = true;
        break;
      }
    }
    return found;
  }

  Future<void> _showFollowUps() async {
    if (_loadingFollowUps) return;
    setState(() => _loadingFollowUps = true);
    try {
      final suggestions =
          await AppScope.of(context).followUpSuggestions(widget.project);
      if (!mounted) return;
      if (suggestions.isEmpty) return;
      final prompt = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Pal.surface,
        barrierColor: Colors.black.withOpacity(0.65),
        builder: (_) => _FollowUpsSheet(suggestions: suggestions),
      );
      if (prompt == null || !mounted) return;
      _composer.text = prompt;
      _composer.selection = TextSelection.collapsed(offset: prompt.length);
      _state?.setPromptDraft(widget.project.id, prompt);
      _scrollToEnd(force: true);
      // A suggestion only fills the composer. The user edits it and decides
      // when to send, so nothing runs from a tap alone.
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not suggest next steps: $error')),
      );
    } finally {
      if (mounted) setState(() => _loadingFollowUps = false);
    }
  }

  Future<void> _send() async {
    final text = _composer.text;
    if ((text.trim().isEmpty && _attachments.isEmpty) || _state?.busy == true) {
      return;
    }
    final files = List<String>.from(_attachments);
    _composer.clear();
    _state?.setPromptDraft(widget.project.id, '');
    setState(() {
      _attachments.clear();
      _liveThinkingOpen = false;
    });
    _scrollToEnd(force: true);
    await AppScope.of(context)
        .send(widget.project.id, text, attachments: files);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final thread = state.threadOf(widget.project.id);
    final liveSignal = state.liveText.length +
        state.liveThinking.length +
        state.liveTools.length;
    if (thread.length != _lastThreadLength || liveSignal != _lastLiveSignal) {
      _lastThreadLength = thread.length;
      _lastLiveSignal = liveSignal;
      _scrollToEnd();
    }

    final showLive = state.busy || state.hasLiveReply;
    final autoOpenThinkingId = _autoOpenThinkingId(thread);
    final todos = state.todosFor(widget.project.id);
    // A run that just ended may have left new snapshots behind.
    if (_lastBusy && !state.busy) unawaited(_loadUndo());
    _lastBusy = state.busy;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: thread.isEmpty && !showLive
                    ? _EmptyAgent(
                        kind: widget.project.kind,
                        onPrompt: (value) {
                          _composer.text = value;
                          _send();
                        },
                      )
                    : SelectionArea(
                        child: ListView.builder(
                          controller: _scroll,
                          // Anchoring the list at its bottom is what keeps a
                          // reopened project on the latest message. Building a
                          // tall transcript forward and jumping once landed
                          // somewhere in the middle while the list estimated
                          // the height of unbuilt entries.
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(
                              Sp.x4, Sp.x4, Sp.x4, Sp.x2),
                          itemCount: thread.length + (showLive ? 1 : 0),
                          itemBuilder: (context, index) {
                            final position =
                                thread.length + (showLive ? 1 : 0) - 1 - index;
                            if (position >= thread.length) {
                              return _LiveReply(
                                key: const ValueKey('live-reply'),
                                text: state.liveText,
                                thinking: state.liveThinking,
                                tools: state.liveTools,
                                busy: state.busy,
                                interrupted: state.liveInterrupted,
                                thinkingOpen: _liveThinkingOpen,
                                onToggleThinking: () => setState(
                                  () => _liveThinkingOpen = !_liveThinkingOpen,
                                ),
                              );
                            }
                            final entry = thread[position];
                            // Without a key, the reversed list reuses the
                            // element at an index for a different entry when a
                            // new one arrives. An open pill then jumped to the
                            // next tool call while the user was reading it.
                            return _EntryView(
                              key: ValueKey(entry.id),
                              entry: entry,
                              project: widget.project,
                              thinkingOpen: _openThinking.contains(entry.id) ||
                                  autoOpenThinkingId == entry.id,
                              onToggleThinking: () {
                                setState(() {
                                  // Manual control wins over carrying the
                                  // live view into the committed entry.
                                  _liveThinkingOpen = false;
                                  if (!_openThinking.remove(entry.id)) {
                                    _openThinking.add(entry.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
              ),
              if (_showJumpToBottom && thread.isNotEmpty)
                Positioned(
                  right: Sp.x4,
                  bottom: Sp.x2,
                  child: _JumpToBottom(
                    onTap: () => _scrollToEnd(force: true),
                  ),
                ),
            ],
          ),
        ),
        if (todos.isNotEmpty)
          _TodoBar(todos: todos, onTap: () => _showTodos(todos)),
        if (state.activeQuota.hasLimit &&
            (state.activeQuota.warning ||
                state.activeQuota.low ||
                state.activeQuota.exhausted))
          _QuotaWarning(
            used: state.activeQuota.used,
            limit: state.activeQuota.limit,
            exhausted: state.activeQuota.exhausted,
          ),
        if (!state.busy &&
            (state.checkpointFor(widget.project.id)?.resumable ?? false))
          _ResumeCard(
            checkpoint: state.checkpointFor(widget.project.id)!,
            onResume: () => state.resumeTask(widget.project.id),
            onDismiss: () => state.dismissCheckpoint(widget.project.id),
          ),
        if (!state.busy && _undoTask != null)
          _UndoBar(
            task: _undoTask!,
            busy: _undoBusy,
            onUndo: _undoLastTask,
          ),
        if (!state.busy && _hasCompletedRun(thread))
          _FollowUpBar(
            loading: _loadingFollowUps,
            onTap: _showFollowUps,
          ),
        if (state.retryAttempt > 0)
          _RetryBanner(
            message: state.retryError,
            attempt: state.retryAttempt,
            total: state.retryTotal,
            seconds: state.retrySeconds,
          ),
        _Composer(
          project: widget.project,
          controller: _composer,
          busy: state.busy,
          stopping: state.stopping,
          attachments: _attachments,
          onAttach: _pickAttachments,
          onRemove: (path) => setState(() => _attachments.remove(path)),
          onSend: _send,
          onStop: state.stop,
        ),
      ],
    );
  }

  /// A round's live reasoning becomes a normal transcript entry when the
  /// round ends. If the live pill was open, keep that same reasoning open so
  /// reading it is not interrupted by the next pill or thinking update.
  String? _autoOpenThinkingId(List<ChatEntry> thread) {
    if (!_liveThinkingOpen) return null;
    for (var index = thread.length - 1; index >= 0; index--) {
      final entry = thread[index];
      if (entry.role == ChatRole.user) return null;
      if (entry.role == ChatRole.assistant &&
          entry.thinking.trim().isNotEmpty) {
        // Remember it too, so a later round cannot collapse the reasoning the
        // user was reading when it becomes a normal transcript entry.
        _openThinking.add(entry.id);
        return entry.id;
      }
    }
    return null;
  }

  Future<void> _showTodos(List<AgentTodo> todos) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => _TodoSheet(todos: todos),
    );
  }
}

class _TodoBar extends StatelessWidget {
  const _TodoBar({required this.todos, required this.onTap});

  final List<AgentTodo> todos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = todos.where((todo) => todo.done).length;
    final active = todos.where((todo) => !todo.done).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x2),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
          decoration: BoxDecoration(
            color: Pal.raised,
            borderRadius: Rd.sm,
            border: Border.all(color: Pal.line),
          ),
          child: Row(
            children: [
              Icon(
                done == todos.length
                    ? Icons.check_circle_rounded
                    : Icons.checklist_rounded,
                size: 17,
                color: done == todos.length ? Pal.mint : Pal.ember,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$done of ${todos.length} steps done',
                      style: Txt.meta.copyWith(fontSize: 9.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active?.text ?? 'All steps complete',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.body.copyWith(
                        fontSize: 11.5,
                        color: active == null ? Pal.mint : Pal.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.expand_less_rounded, size: 16, color: Pal.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodoSheet extends StatelessWidget {
  const _TodoSheet({required this.todos});

  final List<AgentTodo> todos;

  @override
  Widget build(BuildContext context) {
    final done = todos.where((todo) => todo.done).length;
    // The sheet is only as tall as the checklist needs. A two-step plan used
    // to open at 62% of the screen, far away from the bar that was tapped.
    final screen = MediaQuery.sizeOf(context).height;
    final content = 84.0 + todos.length * 44.0;
    final height = (content + MediaQuery.paddingOf(context).bottom)
        .clamp(screen * 0.22, screen * 0.62);
    return SafeArea(
      child: SizedBox(
        height: height.toDouble(),
        child: Column(
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.x2, Sp.x3),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Task checklist', style: Txt.headline),
                        const SizedBox(height: 2),
                        Text(
                          '$done of ${todos.length} complete',
                          style: Txt.meta.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconAction(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            const Hairline(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Sp.page,
                  Sp.x3,
                  Sp.page,
                  Sp.x6,
                ),
                children: [
                  for (final todo in todos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            switch (todo.status) {
                              AgentTodoStatus.completed =>
                                Icons.check_circle_rounded,
                              AgentTodoStatus.inProgress =>
                                Icons.radio_button_checked_rounded,
                              AgentTodoStatus.pending =>
                                Icons.radio_button_unchecked_rounded,
                            },
                            size: 18,
                            color: switch (todo.status) {
                              AgentTodoStatus.completed => Pal.mint,
                              AgentTodoStatus.inProgress => Pal.ember,
                              AgentTodoStatus.pending => Pal.textMuted,
                            },
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  todo.text,
                                  style: Txt.body.copyWith(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: todo.done ? Pal.textMuted : Pal.text,
                                    decoration: todo.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (todo.status == AgentTodoStatus.inProgress)
                                  Text(
                                    'In progress',
                                    style: Txt.meta.copyWith(
                                      fontSize: 9,
                                      color: Pal.ember,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAgent extends StatelessWidget {
  const _EmptyAgent({required this.kind, required this.onPrompt});

  final ProjectKind kind;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final suggestions = switch (kind) {
      ProjectKind.web => const [
          'Add a responsive navigation bar',
          'Add a dark mode toggle to app.js',
          'Improve the landing page copy and layout',
        ],
      ProjectKind.flutter => const [
          'Add a settings screen with a theme switch',
          'Fix any layout overflow on a narrow screen',
          'Add a widget test for the main screen',
        ],
      ProjectKind.python => const [
          'Add command-line arguments to main.py',
          'Write tests for the Python functions',
          'Add a JSON configuration loader',
        ],
      ProjectKind.node => const [
          'Add a JSON API route to server.js',
          'Add request logging and graceful shutdown',
          'Write a test for the Node.js server',
        ],
      ProjectKind.php => const [
          'Add a form handler to index.php',
          'Add a JSON API endpoint',
          'Add input validation and error handling',
        ],
      ProjectKind.go => const [
          'Add an HTTP health endpoint',
          'Add command-line flags to main.go',
          'Write a Go test for the handler',
        ],
      ProjectKind.blank => const [
          'Create a README for this project',
          'Scaffold a small web app',
          'List the files and explain them',
        ],
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x6, Sp.page, Sp.x4),
      children: [
        Text('Ask for a change.', style: Txt.headline),
        const SizedBox(height: Sp.x4),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onPrompt(suggestion),
              behavior: HitTestBehavior.opaque,
              child: Panel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Text(suggestion, style: Txt.bodySoft),
              ),
            ),
          ),
      ],
    );
  }
}

class _EntryView extends StatelessWidget {
  const _EntryView({
    super.key,
    required this.entry,
    required this.project,
    required this.thinkingOpen,
    required this.onToggleThinking,
  });

  final ChatEntry entry;
  final Project project;
  final bool thinkingOpen;
  final VoidCallback onToggleThinking;

  @override
  Widget build(BuildContext context) {
    switch (entry.role) {
      case ChatRole.user:
        return _UserBubble(entry: entry, project: project);
      case ChatRole.assistant:
        return Padding(
          padding: const EdgeInsets.only(bottom: Sp.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.thinking.trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                _ThinkingPill(
                  text: entry.thinking,
                  open: thinkingOpen,
                  onToggle: onToggleThinking,
                ),
              ],
              if (entry.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                _MessageText(entry.text),
              ],
            ],
          ),
        );
      case ChatRole.tool:
        return _ToolPill(entry: entry, project: project);
      case ChatRole.activity:
        return _ActivityPill(entry: entry);
      case ChatRole.error:
        return Padding(
          padding: const EdgeInsets.only(bottom: Sp.x4),
          child: Panel(
            borderColor: Pal.rose.withOpacity(0.45),
            padding: const EdgeInsets.all(Sp.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 17, color: Pal.rose),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    entry.text,
                    style: Txt.bodySoft.copyWith(color: Pal.rose),
                  ),
                ),
              ],
            ),
          ),
        );
      case ChatRole.note:
        return Padding(
          padding: const EdgeInsets.only(bottom: Sp.x4),
          child: Row(
            children: [
              Expanded(child: Container(height: 1, color: Pal.line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 11, color: Pal.textDim),
                    const SizedBox(width: 4),
                    Text(
                      entry.text,
                      style: Txt.meta.copyWith(fontSize: 9),
                    ),
                  ],
                ),
              ),
              Expanded(child: Container(height: 1, color: Pal.line)),
            ],
          ),
        );
    }
  }
}

class _ActivityPill extends StatelessWidget {
  const _ActivityPill({required this.entry});

  final ChatEntry entry;

  IconData get _icon => switch (entry.tool) {
        'compact' => Icons.compress_rounded,
        'skill' => Icons.auto_stories_outlined,
        _ => Icons.data_object_rounded,
      };

  String get _label => switch (entry.tool) {
        'compact' => 'Compacted context',
        'skill' => 'Read skill',
        _ => 'Read context',
      };

  @override
  Widget build(BuildContext context) {
    final detail = entry.detail.trim();
    final color = entry.tool == 'compact' ? Pal.amber : Pal.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Pal.raised,
          borderRadius: Rd.pill,
          border: Border.all(color: Pal.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(
              _label,
              style: Txt.meta.copyWith(
                fontSize: 10,
                color: Pal.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(fontSize: 9.5, color: Pal.textDim),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageText extends StatelessWidget {
  const _MessageText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return ChatMarkdown(text, style: Txt.body.copyWith(height: 1.58));
  }
}

class _LiveReply extends StatelessWidget {
  const _LiveReply({
    super.key,
    required this.text,
    required this.thinking,
    required this.tools,
    required this.busy,
    required this.interrupted,
    required this.thinkingOpen,
    required this.onToggleThinking,
  });

  final String text;
  final String thinking;
  final List<ToolDraft> tools;
  final bool busy;
  final bool interrupted;
  final bool thinkingOpen;
  final VoidCallback onToggleThinking;

  @override
  Widget build(BuildContext context) {
    if (!busy && text.isEmpty && thinking.isEmpty && tools.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thinking.isNotEmpty) ...[
            const SizedBox(height: 7),
            _ThinkingPill(
              text: thinking,
              live: true,
              open: thinkingOpen,
              onToggle: onToggleThinking,
            ),
          ],
          if (interrupted) ...[
            const SizedBox(height: 6),
            Text(
              'Interrupted, reconnecting…',
              style: Txt.meta.copyWith(color: Pal.ember),
            ),
          ],
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Opacity(
                    opacity: interrupted ? 0.55 : 1,
                    child: _MessageText(text),
                  ),
                ),
                const _StreamCaret(),
              ],
            ),
          ] else if (busy && tools.isEmpty) ...[
            const SizedBox(height: 7),
            Text(
              interrupted ? 'Reconnecting…' : 'Thinking…',
              style: Txt.meta.copyWith(color: Pal.textDim),
            ),
          ],
          for (final tool in tools)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: _DraftPill(draft: tool),
            ),
        ],
      ),
    );
  }
}

class _StreamCaret extends StatefulWidget {
  const _StreamCaret();

  @override
  State<_StreamCaret> createState() => _StreamCaretState();
}

class _StreamCaretState extends State<_StreamCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 15,
        margin: const EdgeInsets.only(left: 3, top: 4),
        color: Pal.ember,
      ),
    );
  }
}

class _DraftPill extends StatelessWidget {
  const _DraftPill({required this.draft});

  final ToolDraft draft;

  String get _verb => switch (draft.tool) {
        'write_file' => 'Writing',
        'read_file' => 'Reading',
        'run_command' => 'Running',
        'list_files' => 'Listing',
        _ => 'Running',
      };

  IconData get _icon => switch (draft.tool) {
        'write_file' => Icons.edit_note_rounded,
        'read_file' => Icons.description_outlined,
        'run_command' => Icons.terminal_rounded,
        'list_files' => Icons.folder_open_rounded,
        _ => Icons.build_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.ember.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          _PulseDot(),
          const SizedBox(width: 7),
          Icon(_icon, size: 14, color: Pal.ember),
          const SizedBox(width: 7),
          Text(
            draft.tool,
            style: Txt.meta.copyWith(
              color: Pal.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              draft.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Txt.meta.copyWith(fontSize: 10, color: Pal.textDim),
            ),
          ),
          Text(
            '$_verb…',
            style: Txt.meta.copyWith(
              fontSize: 9.5,
              color: Pal.ember,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_controller),
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: Pal.ember,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.entry, required this.project});

  final ChatEntry entry;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('YOU', style: Txt.overline.copyWith(color: Pal.textDim)),
          const SizedBox(height: 5),
          Container(
            constraints: BoxConstraints(maxWidth: width * 0.84),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: Pal.ember.withOpacity(0.10),
              border: Border.all(color: Pal.ember.withOpacity(0.22)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.text, style: Txt.body.copyWith(fontSize: 14.5)),
                if (entry.attachments.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final path in entry.attachments)
                        _AttachmentPreview(
                          path: path,
                          absolute: state.attachmentPath(project, path),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.path, required this.absolute});

  final String path;
  final String absolute;

  bool get _isImage =>
      RegExp(r'\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false)
          .hasMatch(path);

  String get _name => path.split('/').last;

  @override
  Widget build(BuildContext context) {
    if (_isImage) {
      return ClipRRect(
        borderRadius: Rd.sm,
        child: Image.file(
          File(absolute),
          width: 84,
          height: 84,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) =>
              MonoChip(_name, icon: Icons.image_outlined),
        ),
      );
    }
    return MonoChip(_name, icon: Icons.description_outlined);
  }
}

class _ThinkingPill extends StatefulWidget {
  const _ThinkingPill({
    required this.text,
    required this.open,
    required this.onToggle,
    this.live = false,
  });

  final String text;
  final bool live;
  final bool open;
  final VoidCallback onToggle;

  @override
  State<_ThinkingPill> createState() => _ThinkingPillState();
}

class _ThinkingPillState extends State<_ThinkingPill> {
  final _scroll = ScrollController();
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _ThinkingPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open) _stickToBottom = true;
    if (widget.open &&
        (!oldWidget.open || oldWidget.text.length != widget.text.length)) {
      _scrollToEnd();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearBottom =
        _scroll.position.maxScrollExtent - _scroll.position.pixels <= 40;
    _stickToBottom = nearBottom;
  }

  void _scrollToEnd() {
    if (!_stickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: widget.onToggle,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Pal.raised,
              borderRadius: Rd.pill,
              border: Border.all(color: Pal.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.live
                      ? Icons.psychology_rounded
                      : Icons.psychology_alt_outlined,
                  size: 13,
                  color: widget.live ? Pal.ember : Pal.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.live ? 'Thinking live' : 'Thinking',
                  style: Txt.meta.copyWith(
                    color: widget.live ? Pal.text : Pal.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  widget.open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 15,
                  color: Pal.textDim,
                ),
              ],
            ),
          ),
        ),
        if (widget.open)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              color: Pal.ghBg,
              borderRadius: Rd.sm,
              border: Border.all(color: Pal.ghLine),
            ),
            child: SingleChildScrollView(
              controller: _scroll,
              child: Text(
                widget.text,
                style: Txt.code.copyWith(
                  fontSize: 11,
                  height: 1.55,
                  color: Pal.ghMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Puts every file the last task changed back the way it was. Only shown when
/// a snapshot exists, so it never offers an undo that cannot happen.
class _UndoBar extends StatelessWidget {
  const _UndoBar({
    required this.task,
    required this.busy,
    required this.onUndo,
  });

  final UndoTask task;
  final bool busy;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final count = task.fileCount;
    final label = task.label.isEmpty ? 'Last task' : task.label;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 8, 8, 8),
        decoration: BoxDecoration(
          color: Pal.raised,
          borderRadius: Rd.sm,
          border: Border.all(color: Pal.line),
        ),
        child: Row(
          children: [
            Icon(Icons.undo_rounded, size: 16, color: Pal.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Undo last task',
                    style: Txt.meta.copyWith(fontSize: 9.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count ${count == 1 ? 'file' : 'files'} · $label',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.body.copyWith(
                      fontSize: 11.5,
                      color: Pal.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: busy ? null : onUndo,
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                button: true,
                label: 'Undo the last task',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: Rd.pill,
                    border: Border.all(color: Pal.lineStrong),
                  ),
                  child: busy
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: Pal.textMuted,
                          ),
                        )
                      : Text(
                          'Undo',
                          style: Txt.meta.copyWith(
                            fontSize: 10.5,
                            color: Pal.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolPill extends StatefulWidget {
  const _ToolPill({required this.entry, required this.project});

  final ChatEntry entry;
  final Project project;

  @override
  State<_ToolPill> createState() => _ToolPillState();
}

class _ToolPillState extends State<_ToolPill> {
  bool _open = false;
  bool _reverting = false;

  ChatEntry get entry => widget.entry;

  bool get _canRevert =>
      entry.ok && entry.undoIds.isNotEmpty && !entry.reverted;

  Future<void> _revert() async {
    if (_reverting) return;
    final state = AppScope.of(context);
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Revert this change?',
      body: entry.tool.startsWith('write_files') || entry.tool == 'apply_patch'
          ? 'Every file this call wrote goes back to how it was just before '
              'it ran. Later changes to the same files are left alone.'
          : '${entry.detail} goes back to how it was just before this call. '
              'Later changes to the same file are left alone.',
      confirmLabel: 'Revert change',
      destructive: true,
      icon: Icons.undo_rounded,
      details: [
        ConfirmDetail('Tool', entry.tool),
        ConfirmDetail('Path', entry.detail)
      ],
    );
    if (!confirmed || !mounted) return;
    setState(() => _reverting = true);
    try {
      final message = await state.revertChanges(widget.project, entry);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not revert: $error')),
      );
    } finally {
      if (mounted) setState(() => _reverting = false);
    }
  }

  IconData get _icon => switch (entry.tool) {
        'write_file' => Icons.edit_note_rounded,
        'read_file' => Icons.description_outlined,
        'read_files' => Icons.description_outlined,
        'run_command' => Icons.terminal_rounded,
        'list_files' => Icons.folder_open_rounded,
        _ => Icons.build_outlined,
      };

  bool get _failed => entry.text.toLowerCase().startsWith('error') || !entry.ok;

  @override
  Widget build(BuildContext context) {
    final diff = FileDiff.decode(entry.patch);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Pal.raised,
                borderRadius: Rd.sm,
                border: Border.all(
                  color: _failed ? Pal.rose.withOpacity(0.4) : Pal.line,
                ),
              ),
              child: Row(
                children: [
                  Icon(_icon, size: 14, color: _failed ? Pal.rose : Pal.mint),
                  const SizedBox(width: 7),
                  Text(
                    entry.tool,
                    style: Txt.meta.copyWith(
                      color: _failed ? Pal.rose : Pal.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      entry.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Txt.meta.copyWith(fontSize: 10, color: Pal.textDim),
                    ),
                  ),
                  if (entry.added > 0 || entry.removed > 0) ...[
                    Text(
                      '+${entry.added}',
                      style: Txt.meta.copyWith(
                        fontSize: 10,
                        color: Pal.ghAddText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '-${entry.removed}',
                      style: Txt.meta.copyWith(
                        fontSize: 10,
                        color: Pal.ghDelText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (entry.reverted)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 12,
                            color: Pal.mint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Reverted',
                            style: Txt.meta.copyWith(
                              fontSize: 9.5,
                              color: Pal.mint,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_canRevert)
                    GestureDetector(
                      onTap: _reverting ? null : _revert,
                      behavior: HitTestBehavior.opaque,
                      child: Semantics(
                        button: true,
                        label: 'Revert ${entry.detail}',
                        child: Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: Rd.pill,
                            border: Border.all(color: Pal.lineStrong),
                          ),
                          child: _reverting
                              ? SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.4,
                                    color: Pal.textMuted,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.undo_rounded,
                                      size: 11,
                                      color: Pal.textMuted,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Revert',
                                      style: Txt.meta.copyWith(
                                        fontSize: 9.5,
                                        color: Pal.textMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: Pal.textDim,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            GestureDetector(
              onTap: () => setState(() => _open = false),
              behavior: HitTestBehavior.opaque,
              child: _ToolBody(entry: entry, diff: diff),
            ),
        ],
      ),
    );
  }
}

class _ToolBody extends StatelessWidget {
  const _ToolBody({required this.entry, required this.diff});

  final ChatEntry entry;
  final FileDiff? diff;

  @override
  Widget build(BuildContext context) {
    final content = entry.text.trim();
    if (diff != null && diff!.rows.isNotEmpty) {
      return _DiffTable(diff: diff!);
    }
    if (content.isEmpty) return const SizedBox.shrink();
    if (entry.tool == 'read_files') {
      return _ReadFilesBody(text: content);
    }
    final numbered = entry.tool == 'read_file' || entry.tool == 'list_files';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        color: Pal.ghBg,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.ghLine),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: numbered
              ? _NumberedText(text: content)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    content,
                    style: Txt.code.copyWith(
                      fontSize: 11,
                      height: 1.55,
                      color: entry.tool == 'run_command'
                          ? Pal.ghText
                          : Pal.ghMuted,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Only additions and removals are shown. Unchanged lines stay out of the
/// transcript; the line numbers make the surrounding code legible.
class _DiffTable extends StatelessWidget {
  const _DiffTable({required this.diff});

  final FileDiff diff;

  @override
  Widget build(BuildContext context) {
    final rows = diff.rows
        .where((row) => row.kind != DiffKind.context)
        .toList(growable: false);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        color: Pal.ghBg,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.ghLine),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final added = row.kind == DiffKind.added;
            final removed = row.kind == DiffKind.removed;
            return Container(
              color: added
                  ? Pal.ghAddBg
                  : removed
                      ? Pal.ghDelBg
                      : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      row.oldLine?.toString() ?? '',
                      textAlign: TextAlign.right,
                      style: Txt.meta.copyWith(
                        fontSize: 9,
                        height: 1.55,
                        color: Pal.ghMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: 30,
                    child: Text(
                      row.newLine?.toString() ?? '',
                      textAlign: TextAlign.right,
                      style: Txt.meta.copyWith(
                        fontSize: 9,
                        height: 1.55,
                        color: Pal.ghMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: 10,
                    child: Text(
                      added ? '+' : '-',
                      style: Txt.meta.copyWith(
                        fontSize: 10,
                        height: 1.4,
                        color: added ? Pal.ghAddText : Pal.ghDelText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.text.isEmpty ? ' ' : row.text,
                      style: Txt.code.copyWith(
                        fontSize: 10.5,
                        height: 1.45,
                        color: Pal.ghText,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NumberedText extends StatelessWidget {
  const _NumberedText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final shown = lines.length <= 400 ? lines : lines.take(400).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.right,
                    style: Txt.meta.copyWith(
                      fontSize: 9,
                      height: 1.5,
                      color: Pal.ghMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    shown[i].isEmpty ? ' ' : shown[i],
                    style: Txt.code.copyWith(
                      fontSize: 10.5,
                      height: 1.45,
                      color: Pal.ghText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (lines.length > 400)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              '… ${lines.length - 400} more lines',
              style: Txt.meta.copyWith(color: Pal.textDim),
            ),
          ),
      ],
    );
  }
}

class _FollowUpBar extends StatelessWidget {
  const _FollowUpBar({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x3, 0, Sp.x3, Sp.x1),
      child: GestureDetector(
        onTap: loading ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: Pal.raised,
            borderRadius: Rd.sm,
            border: Border.all(color: Pal.line),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 15, color: Pal.ember),
              const SizedBox(width: 7),
              Text(
                'Next steps',
                style: Txt.label.copyWith(
                  fontSize: 11.5,
                  color: Pal.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'turn this result into the next task',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(fontSize: 9),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                Icon(Icons.arrow_forward_rounded, size: 14, color: Pal.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowUpsSheet extends StatelessWidget {
  const _FollowUpsSheet({required this.suggestions});

  final List<FollowUpSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Text('What next?', style: Txt.headline),
            const SizedBox(height: 4),
            Text(
              'Tap one to add it to the prompt, then edit or send it yourself.',
              style: Txt.meta,
            ),
            const SizedBox(height: Sp.x4),
            for (final suggestion in suggestions) ...[
              GestureDetector(
                onTap: () => Navigator.of(context).pop(suggestion.prompt),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(Sp.x3),
                  decoration: BoxDecoration(
                    color: Pal.raised,
                    borderRadius: Rd.md,
                    border: Border.all(color: Pal.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Pal.ember.withOpacity(0.10),
                          borderRadius: Rd.sm,
                        ),
                        child: Icon(Icons.north_east_rounded,
                            size: 14, color: Pal.ember),
                      ),
                      const SizedBox(width: Sp.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestion.title,
                              style: Txt.title.copyWith(fontSize: 13.5),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              suggestion.prompt,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Txt.bodySoft.copyWith(fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_upward_rounded,
                          size: 16, color: Pal.textDim),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RetryBanner extends StatelessWidget {
  const _RetryBanner({
    required this.message,
    required this.attempt,
    required this.total,
    required this.seconds,
  });

  final String message;
  final int attempt;
  final int total;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final detail = message.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x4, 0, Sp.x4, Sp.x2),
      child: Container(
        padding: const EdgeInsets.all(Sp.x3),
        decoration: BoxDecoration(
          color: Pal.rose.withOpacity(0.08),
          borderRadius: Rd.sm,
          border: Border.all(color: Pal.rose.withOpacity(0.40)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 16, color: Pal.rose),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Retrying $attempt/$total in ${seconds}s',
                    style: Txt.label.copyWith(
                      color: Pal.rose,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.meta.copyWith(fontSize: 9.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.project,
    required this.controller,
    required this.busy,
    required this.stopping,
    required this.attachments,
    required this.onAttach,
    required this.onRemove,
    required this.onSend,
    required this.onStop,
  });

  final Project project;
  final TextEditingController controller;
  final bool busy;
  final bool stopping;
  final List<String> attachments;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemove;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final List<_ComposerSuggestion> _suggestions = [];
  final List<_ComposerSuggestion> _skills = [];
  List<String>? _files;
  Timer? _debounce;
  String? _trigger;
  int _tokenStart = 0;
  bool _loadedContext = false;
  bool _loadingFiles = false;
  bool _loadingSkills = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadedContext) {
      _loadedContext = true;
      _loadSkills();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  Future<void> _loadSkills() async {
    if (_loadingSkills) return;
    _loadingSkills = true;
    final state = AppScope.of(context);
    final projectSkills = await state.installedSkillsFor(widget.project);
    if (!mounted) {
      _loadingSkills = false;
      return;
    }
    _skills.clear();
    final seen = <String>{};
    void add(String label, String command, String detail) {
      if (!seen.add(command)) return;
      _skills.add(_ComposerSuggestion(
        label: label,
        insert: '/$command ',
        detail: detail,
        icon: Icons.extension_outlined,
      ));
    }

    // Disabled skills are listed too: typing their command applies them for
    // that one prompt without turning the skill back on everywhere.
    for (final skill in state.skills) {
      final command =
          skill.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      if (command.isNotEmpty) {
        add(
          skill.name,
          command,
          skill.enabled ? 'Enabled skill' : 'Disabled skill',
        );
      }
    }
    for (final skill in projectSkills) {
      add(skill.name, skill.slug, 'Project skill');
    }
    _skills.sort((a, b) => a.label.compareTo(b.label));
    _loadingSkills = false;
    if (mounted) _refreshSuggestions();
  }

  Future<void> _loadFiles() async {
    if (_loadingFiles || _files != null) return;
    _loadingFiles = true;
    final state = AppScope.of(context);
    try {
      final entries =
          await state.fsFor(widget.project).list(includeHidden: true);
      if (!mounted) return;
      _files = [
        for (final entry in entries)
          if (!entry.isDir && !entry.path.startsWith('.praxis/')) entry.path,
      ]..sort();
      _refreshSuggestions();
    } catch (_) {
      _files = const [];
    } finally {
      _loadingFiles = false;
    }
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 90), _refreshSuggestions);
  }

  void _hideSuggestions() {
    if (_suggestions.isEmpty) return;
    setState(() {
      _suggestions.clear();
      _trigger = null;
    });
  }

  void _refreshSuggestions() {
    if (!mounted) return;
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _hideSuggestions();
      return;
    }
    final before = widget.controller.text.substring(0, selection.baseOffset);
    final match =
        RegExp(r'(?:^|\s)([/@])([A-Za-z0-9._/-]*)$').firstMatch(before);
    if (match == null) {
      _hideSuggestions();
      return;
    }
    final trigger = match.group(1)!;
    final query = match.group(2)!.toLowerCase();
    if (trigger == '/' && query.isEmpty) {
      _hideSuggestions();
      return;
    }
    if (trigger == '@' && _files == null) {
      _loadFiles();
    }
    final tokenStart = selection.baseOffset - query.length - 1;
    final pool = trigger == '/'
        ? _skills
        : [
            for (final path in _files ?? const <String>[])
              _ComposerSuggestion(
                label: path.split('/').last,
                insert: '@$path ',
                detail: path,
                icon: Icons.description_outlined,
              ),
          ];
    final filtered = pool
        .where((item) =>
            query.isEmpty ||
            item.label.toLowerCase().contains(query) ||
            item.detail.toLowerCase().contains(query))
        .take(7)
        .toList();
    setState(() {
      _trigger = trigger;
      _query = query;
      _tokenStart = tokenStart < 0 ? 0 : tokenStart;
      _suggestions
        ..clear()
        ..addAll(filtered);
    });
  }

  /// Marks the typed part of a skill or file name inside the suggestion so the
  /// match is visible instead of being one undifferentiated row.
  Widget _highlightSuggestion(String label) {
    final style = Txt.code.copyWith(fontSize: 11);
    final index =
        _query.isEmpty ? -1 : label.toLowerCase().indexOf(_query.toLowerCase());
    if (index < 0 || index + _query.length > label.length) {
      return Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label.substring(0, index)),
          TextSpan(
            text: label.substring(index, index + _query.length),
            style: style.copyWith(
              color: Pal.ember,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: label.substring(index + _query.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  void _choose(_ComposerSuggestion suggestion) {
    final selection = widget.controller.selection;
    if (!selection.isValid) return;
    final text = widget.controller.text;
    final caret = selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, caret);
    final match =
        RegExp(r'(?:^|\s)([/@])([A-Za-z0-9._/-]*)$').firstMatch(before);
    // Work out the token from the text that is on screen now. A suggestion can
    // arrive after the caret moved, and replacing a stale range deleted part of
    // the command the user had already typed.
    final start = match == null
        ? _tokenStart.clamp(0, caret)
        : caret - match.group(2)!.length - 1;
    final updated = text.replaceRange(start, caret, suggestion.insert);
    widget.controller.value = TextEditingValue(
      text: updated,
      // A collapsed caret keeps the completion. Selecting it meant the next key
      // press replaced the whole skill name with that letter.
      selection: TextSelection.collapsed(
        offset: start + suggestion.insert.length,
      ),
    );
    setState(() {
      _suggestions.clear();
      _trigger = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(Sp.x3, 0, Sp.x3, 4),
            decoration: BoxDecoration(
              color: Pal.surface,
              borderRadius: Rd.md,
              border: Border.all(color: Pal.lineStrong),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(Pal.isDark ? 0.28 : 0.08),
                  offset: const Offset(0, 4),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 3),
                  child: Row(
                    children: [
                      Icon(
                        _trigger == '/'
                            ? Icons.bolt_rounded
                            : Icons.tag_rounded,
                        size: 13,
                        color: Pal.ember,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _trigger == '/' ? 'Skills' : 'Project files',
                          style: Txt.meta.copyWith(fontSize: 8.5),
                        ),
                      ),
                      if (_trigger == '/')
                        IconAction(
                          icon: Icons.refresh_rounded,
                          tooltip: 'Refresh skills',
                          size: 14,
                          padding: const EdgeInsets.all(3),
                          onTap: _loadingSkills ? null : _loadSkills,
                        ),
                    ],
                  ),
                ),
                for (final suggestion in _suggestions)
                  InkWell(
                    onTap: () => _choose(suggestion),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                      child: Row(
                        children: [
                          Icon(suggestion.icon, size: 14, color: Pal.mint),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _highlightSuggestion(suggestion.label),
                                if (suggestion.detail.isNotEmpty)
                                  Text(
                                    suggestion.detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Txt.meta.copyWith(fontSize: 8.5),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            _trigger == '/' ? suggestion.insert.trim() : '@',
                            style: Txt.meta.copyWith(
                              fontSize: 8.5,
                              color: Pal.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        _ComposerBody(
          controller: widget.controller,
          busy: widget.busy,
          stopping: widget.stopping,
          attachments: widget.attachments,
          onAttach: widget.onAttach,
          onRemove: widget.onRemove,
          onSend: widget.onSend,
          onStop: widget.onStop,
        ),
      ],
    );
  }
}

class _ComposerSuggestion {
  const _ComposerSuggestion({
    required this.label,
    required this.insert,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String insert;
  final String detail;
  final IconData icon;
}

class _ComposerBody extends StatelessWidget {
  const _ComposerBody({
    required this.controller,
    required this.busy,
    required this.stopping,
    required this.attachments,
    required this.onAttach,
    required this.onRemove,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool busy;
  final bool stopping;
  final List<String> attachments;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemove;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Sp.x3,
        Sp.x1,
        Sp.x3,
        mathMax(12, MediaQuery.paddingOf(context).bottom + 8),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
        decoration: BoxDecoration(
          color: Pal.surface,
          borderRadius: Rd.lg,
          border: Border.all(color: Pal.lineStrong),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(Pal.isDark ? 0.30 : 0.08),
              offset: const Offset(0, 6),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: attachments.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final path = attachments[index];
                      final name = path.split('/').last;
                      return Container(
                        padding: const EdgeInsets.only(left: 9, right: 4),
                        decoration: BoxDecoration(
                          color: Pal.raised,
                          borderRadius: Rd.pill,
                          border: Border.all(color: Pal.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.attach_file_rounded,
                                size: 12, color: Pal.textDim),
                            const SizedBox(width: 5),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Txt.meta.copyWith(fontSize: 10),
                              ),
                            ),
                            IconAction(
                              icon: Icons.close_rounded,
                              tooltip: 'Remove attachment',
                              size: 12,
                              onTap: () => onRemove(path),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: IconAction(
                      icon: Icons.attach_file_rounded,
                      tooltip: 'Attach a photo or file',
                      size: 19,
                      onTap: busy ? null : onAttach,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: Txt.body.copyWith(fontSize: 14),
                    cursorColor: Pal.ember,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      filled: true,
                      fillColor: Pal.raised,
                      hintText: busy
                          ? (stopping ? 'Stopping…' : 'Working…')
                          : 'Ask for a change',
                      hintStyle: Txt.bodySoft.copyWith(color: Pal.textDim),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: Rd.md,
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: Rd.md,
                        borderSide:
                            BorderSide(color: Pal.ember.withOpacity(0.45)),
                      ),
                    ),
                    onSubmitted: busy ? null : (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 7),
                Semantics(
                  button: true,
                  label: busy
                      ? (stopping ? 'Stopping' : 'Stop this response')
                      : 'Send',
                  child: GestureDetector(
                    onTap: busy ? (stopping ? null : onStop) : onSend,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: busy ? Pal.rose : Pal.ember,
                        borderRadius: Rd.md,
                      ),
                      child: stopping
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Pal.onEmber,
                              ),
                            )
                          : Icon(
                              busy
                                  ? Icons.stop_rounded
                                  : Icons.arrow_upward_rounded,
                              size: 20,
                              color: Pal.onEmber,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JumpToBottom extends StatelessWidget {
  const _JumpToBottom({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Jump to latest message',
      child: Tooltip(
        message: 'Jump to latest',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Pal.surface,
              shape: BoxShape.circle,
              border: Border.all(color: Pal.ember.withOpacity(0.42)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(Pal.isDark ? 0.26 : 0.08),
                  offset: const Offset(0, 4),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Icon(
              Icons.keyboard_double_arrow_down_rounded,
              size: 21,
              color: Pal.ember,
            ),
          ),
        ),
      ),
    );
  }
}

double mathMax(double a, double b) => a > b ? a : b;

class _QuotaWarning extends StatelessWidget {
  const _QuotaWarning({
    required this.used,
    required this.limit,
    required this.exhausted,
  });

  final int used;
  final int limit;
  final bool exhausted;

  @override
  Widget build(BuildContext context) {
    final color = Pal.amber;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.x3, 0, Sp.x3, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: Rd.sm,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.speed_rounded, size: 14, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              exhausted
                  ? '$used/$limit requests used today. This is a local count only; sending still works.'
                  : '$used/$limit requests used today.',
              style: Txt.meta.copyWith(fontSize: 9.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.checkpoint,
    required this.onResume,
    required this.onDismiss,
  });

  final TaskCheckpoint checkpoint;
  final VoidCallback onResume;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.x3, 0, Sp.x3, 6),
      padding: const EdgeInsets.fromLTRB(11, 10, 8, 8),
      decoration: BoxDecoration(
        color: Pal.ember.withOpacity(0.07),
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.ember.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restore_rounded, size: 15, color: Pal.ember),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Task paused · ${checkpoint.completed.length} completed',
                  style: Txt.label.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconAction(
                icon: Icons.close_rounded,
                tooltip: 'Dismiss checkpoint',
                size: 15,
                onTap: onDismiss,
              ),
            ],
          ),
          if (checkpoint.pendingStep.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(
                checkpoint.pendingStep,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Txt.meta.copyWith(fontSize: 9.5, height: 1.4),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${checkpoint.changedFiles.length} changed files · '
                  '${checkpoint.providerName} ${checkpoint.model}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.meta.copyWith(fontSize: 8.5),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onResume,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Pal.ember,
                    borderRadius: Rd.sm,
                  ),
                  child: Text(
                    'Resume',
                    style: Txt.label.copyWith(
                      fontSize: 10,
                      color: Pal.onEmber,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadFilesBody extends StatelessWidget {
  const _ReadFilesBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final matches =
        RegExp(r'^\[(.+?) · lines', multiLine: true).allMatches(text).toList();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.line),
      ),
      child: matches.isEmpty
          ? Text(
              text,
              style: Txt.code.copyWith(fontSize: 10.5, height: 1.5),
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final match in matches)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Pal.surface,
                      borderRadius: Rd.sm,
                      border: Border.all(color: Pal.line),
                    ),
                    // A long repository path used to grow the pill past the
                    // right edge of the transcript. Keep it inside the chat
                    // column and ellipsize it instead.
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 72,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined,
                            size: 12, color: Pal.sky),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Tooltip(
                            message: match.group(1) ?? '',
                            child: Text(
                              match.group(1) ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Txt.code.copyWith(fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
