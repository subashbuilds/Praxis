import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/round_log.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/screens/logs_screen.dart';
import 'package:praxis/state/app_state.dart';

class _LogsState extends AppState {
  _LogsState(this._tasks)
      : super(
          root: Directory.systemTemp,
          store: MemoryStore(),
          seedWelcome: false,
        );

  final List<AgentTask> _tasks;

  @override
  Future<List<AgentTask>> loadAgentTasks() async => _tasks;
}

void main() {
  testWidgets('logs screen renders the aggregate and a task row',
      (tester) async {
    final task = AgentTask(
      taskId: 'task-one',
      outcome: AgentOutcome.completed,
      rounds: [
        AgentRound(
          taskId: 'task-one',
          roundIndex: 0,
          at: DateTime.utc(2026, 11, 7, 10),
          provider: 'openrouter',
          model: 'model',
          toolNames: const ['read_file'],
          type: RoundType.explore,
          repeatedCall: false,
          inputTokens: 8,
          outputTokens: 2,
        ),
      ],
    );
    final state = _LogsState([task]);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: LogsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('1 model request'), findsOneWidget);
    expect(find.text('task-one'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
    // The type appears in both the aggregate and the task card.
    expect(find.text('explore 1'), findsNWidgets(2));
    expect(find.text('No agent rounds yet'), findsNothing);
  });
}
