import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/core/undo_store.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';
import 'package:praxis/workspace/agent_tab.dart';

/// Drives the agent tab without touching disk or a provider: the undo APIs
/// only record the call and report back what the real store would say.
class _UndoUiState extends AppState {
  _UndoUiState(Directory root)
      : super(root: root, store: MemoryStore(), seedWelcome: false);

  final List<ChatEntry> thread = [];
  UndoTask? undoTask;
  int undoCalls = 0;
  int revertCalls = 0;

  @override
  List<ChatEntry> threadOf(String projectId) => thread;

  @override
  Future<void> loadTodos(Project project) async {}

  @override
  Future<UndoTask?> undoableTask(Project project) async => undoTask;

  @override
  Future<String> undoLastTask(Project project) async {
    undoCalls++;
    undoTask = null;
    notifyListeners();
    return 'Undid the last task.';
  }

  @override
  Future<String> revertChanges(Project project, ChatEntry entry) async {
    revertCalls++;
    final index = thread.indexWhere((item) => item.id == entry.id);
    if (index >= 0) thread[index] = thread[index].copyWith(reverted: true);
    notifyListeners();
    return 'Reverted ${entry.detail}.';
  }
}

ChatEntry _write({
  String id = 'tool-1',
  String detail = 'lib/main.dart',
  List<String> undoIds = const ['change-1'],
  bool reverted = false,
}) =>
    ChatEntry(
      id: id,
      role: ChatRole.tool,
      text: 'Wrote 3 lines',
      tool: 'write_file',
      detail: detail,
      undoIds: undoIds,
      reverted: reverted,
      at: DateTime.utc(2026, 11, 27, 9),
    );

UndoTask _task({String label = 'Refactor the header'}) => UndoTask(
      id: 'task-1',
      label: label,
      at: DateTime.utc(2026, 11, 27, 9),
      changes: const [
        FileChange(
          id: 'change-1',
          path: 'lib/main.dart',
          before: 'old\n',
          existed: true,
        ),
        FileChange(
          id: 'change-2',
          path: 'lib/theme.dart',
          before: '',
          existed: false,
        ),
      ],
    );

void main() {
  final project = Project(
    id: 'undo-ui',
    name: 'Undo UI',
    kind: ProjectKind.flutter,
    createdAt: DateTime.utc(2026, 11, 27),
  );

  Future<_UndoUiState> pumpTab(
    WidgetTester tester, {
    UndoTask? undoTask,
  }) async {
    late Directory temp;
    late _UndoUiState state;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('praxis_undo_ui_');
      state = _UndoUiState(temp)..undoTask = undoTask;
    });
    addTearDown(() async {
      state.dispose();
      await temp.delete(recursive: true);
    });
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: Scaffold(body: AgentTab(project: project)),
        ),
      ),
    );
    await tester.pump();
    return state;
  }

  testWidgets('the Revert pill confirms, then shows the change as reverted',
      (tester) async {
    final state = await pumpTab(tester);
    state.thread.add(_write());
    state.notifyListeners();
    await tester.pump();

    expect(find.text('Revert'), findsOneWidget);

    // Backing out of the confirmation leaves the change alone.
    await tester.tap(find.text('Revert'));
    await tester.pump();
    expect(find.text('Revert this change?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(state.revertCalls, 0);
    expect(find.text('Revert'), findsOneWidget);

    await tester.tap(find.text('Revert'));
    await tester.pump();
    await tester.tap(find.text('Revert change'));
    await tester.pump();
    await tester.pump();

    expect(state.revertCalls, 1);
    expect(find.text('Revert'), findsNothing);
    expect(find.text('Reverted'), findsOneWidget);
  });

  testWidgets('only a write with a live snapshot offers a revert',
      (tester) async {
    final state = await pumpTab(tester);
    state.thread
      ..add(_write(id: 'tool-old', undoIds: const []))
      ..add(_write(id: 'tool-done', reverted: true));
    state.notifyListeners();
    await tester.pump();

    expect(find.text('Reverted'), findsOneWidget);
    expect(find.text('Revert'), findsNothing);
  });

  testWidgets('the Undo bar names the last task and undoes it once confirmed',
      (tester) async {
    final state = await pumpTab(tester, undoTask: _task());
    state.thread.add(ChatEntry(
      id: 'assistant-1',
      role: ChatRole.assistant,
      text: 'Done.',
      at: DateTime.utc(2026, 11, 27, 10),
    ));
    state.notifyListeners();
    await tester.pump();

    expect(find.text('Undo last task'), findsOneWidget);
    expect(find.text('2 files · Refactor the header'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(find.text('Undo the last task?'), findsOneWidget);
    expect(find.text('Refactor the header'), findsOneWidget);
    await tester.tap(find.text('Undo task'));
    await tester.pump();
    await tester.pump();

    expect(state.undoCalls, 1);
    expect(find.text('Undo last task'), findsNothing);
  });

  testWidgets('the Undo bar stays hidden when nothing can be undone',
      (tester) async {
    final state = await pumpTab(tester);
    state.thread.add(ChatEntry(
      id: 'assistant-1',
      role: ChatRole.assistant,
      text: 'Done.',
      at: DateTime.utc(2026, 11, 27, 10),
    ));
    state.notifyListeners();
    await tester.pump();

    expect(find.text('Undo last task'), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });
}
