import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/agent_todos.dart';
import 'package:praxis/core/follow_ups.dart';
import 'package:praxis/models.dart';

void main() {
  test('suggestions use changed files, open todos and project type', () {
    final project = Project(
      id: 'demo',
      name: 'Demo',
      kind: ProjectKind.web,
      createdAt: DateTime(2026, 11, 15),
    );
    final suggestions = buildFollowUps(
      project: project,
      thread: [
        ChatEntry(
          id: '1',
          role: ChatRole.user,
          text: 'Change the header',
          at: DateTime(2026, 11, 15),
        ),
        ChatEntry(
          id: '2',
          role: ChatRole.assistant,
          text: 'Updated the header and added a test.',
          at: DateTime(2026, 11, 15),
        ),
      ],
      changedFiles: const ['index.html', 'style.css'],
      todos: const [
        AgentTodo(text: 'Check the mobile layout'),
      ],
      canPush: true,
    );

    expect(suggestions, hasLength(3));
    expect(suggestions.first.title, 'Finish the open step');
    expect(suggestions.first.prompt, contains('Check the mobile layout'));
    expect(
      suggestions.any((item) => item.prompt.contains('index.html')),
      isTrue,
    );
    expect(
      suggestions.any((item) => item.title == 'Commit the result'),
      isFalse,
    );
  });
}
