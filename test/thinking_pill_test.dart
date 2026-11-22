import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';
import 'package:praxis/workspace/agent_tab.dart';

/// A state with a controllable thread and live reply, so the agent tab can be
/// driven without starting a provider request.
class _ThinkingState extends AppState {
  _ThinkingState(Directory root)
      : super(root: root, store: MemoryStore(), seedWelcome: false);

  final List<ChatEntry> thread = [];

  @override
  List<ChatEntry> threadOf(String projectId) => thread;

  @override
  Future<void> loadTodos(Project project) async {}

  void bump() => notifyListeners();
}

void main() {
  testWidgets('live thinking stays open and keeps scrolling to new output',
      (tester) async {
    final project = Project(
      id: 'thinking-project',
      name: 'Thinking',
      kind: ProjectKind.flutter,
      createdAt: DateTime.utc(2026, 11, 22),
    );
    late Directory temp;
    late _ThinkingState state;
    // Real file I/O must run outside the fake async zone of a widget test.
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('praxis_thinking_');
      state = _ThinkingState(temp);
      await state.fsFor(project).ensureRoot();
      await state.fsFor(project).write('README.md', '# Thinking\n');
    });
    addTearDown(() async {
      state.dispose();
      await temp.delete(recursive: true);
    });

    final firstText = List<String>.generate(
      60,
      (index) => 'reasoning line $index ${'x' * 40}',
    ).join('\n');
    state.busy = true;
    state.liveThinking = firstText;

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: Scaffold(body: AgentTab(project: project)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Thinking live'), findsOneWidget);
    await tester.tap(find.text('Thinking live'));
    await tester.pump();
    await tester.pump();

    ScrollController panel() => tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    expect(find.textContaining('reasoning line 59'), findsOneWidget);
    expect(
      panel().position.pixels,
      moreOrLessEquals(panel().position.maxScrollExtent, epsilon: 0.5),
    );

    // New reasoning updates the same pill. It stays open and follows the end.
    state.liveThinking = '$firstText\nnewest reasoning A';
    state.bump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Thinking live'), findsOneWidget);
    expect(find.textContaining('newest reasoning A'), findsOneWidget);
    expect(
      panel().position.pixels,
      moreOrLessEquals(panel().position.maxScrollExtent, epsilon: 0.5),
    );

    // Scrolling up pauses following until the reader returns to the bottom.
    panel().jumpTo(0);
    await tester.pump();
    state.liveThinking = '${state.liveThinking}\nnewest reasoning B';
    state.bump();
    await tester.pump();
    await tester.pump();
    expect(panel().position.pixels, 0);

    panel().jumpTo(panel().position.maxScrollExtent);
    await tester.pump();
    state.liveThinking = '${state.liveThinking}\nnewest reasoning C';
    state.bump();
    await tester.pump();
    await tester.pump();
    expect(
      panel().position.pixels,
      moreOrLessEquals(panel().position.maxScrollExtent, epsilon: 0.5),
    );

    // The round ends: the live reasoning becomes a transcript entry and must
    // stay open instead of collapsing when the live reply disappears.
    final completedText = state.liveThinking;
    state.busy = false;
    state.liveThinking = '';
    state.thread.add(ChatEntry(
      id: 'assistant-1',
      role: ChatRole.assistant,
      text: 'First answer.',
      thinking: completedText,
      at: DateTime.utc(2026, 11, 22, 10),
    ));
    state.bump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.textContaining('newest reasoning C'), findsOneWidget);

    // A later round adds another pill without closing the one being read.
    state.thread.add(ChatEntry(
      id: 'assistant-2',
      role: ChatRole.assistant,
      text: 'Second answer.',
      thinking: 'second round reasoning',
      at: DateTime.utc(2026, 11, 22, 11),
    ));
    state.bump();
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('newest reasoning C'), findsOneWidget);
    expect(find.textContaining('second round reasoning'), findsOneWidget);
  });
}
