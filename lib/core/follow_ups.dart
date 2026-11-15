import '../models.dart';
import 'agent_todos.dart';

class FollowUpSuggestion {
  const FollowUpSuggestion({required this.title, required this.prompt});

  final String title;
  final String prompt;
}

/// Builds a short set of next actions from the finished task, the files it
/// changed and any open checklist items. Nothing here runs automatically: the
/// UI only fills the composer with a prompt the user can edit or send.
List<FollowUpSuggestion> buildFollowUps({
  required Project project,
  required List<ChatEntry> thread,
  required List<String> changedFiles,
  required List<AgentTodo> todos,
  bool canPush = false,
}) {
  final suggestions = <FollowUpSuggestion>[];
  void add(String title, String prompt) {
    if (suggestions.any((item) => item.title == title)) return;
    suggestions.add(FollowUpSuggestion(title: title, prompt: prompt));
  }

  final openTodo = todos.where((todo) => !todo.done).firstOrNull;
  if (openTodo != null) {
    add(
      'Finish the open step',
      'Continue with this remaining step and verify the result: '
          '${openTodo.text}',
    );
  }

  final files = changedFiles.take(4).toList();
  if (files.isNotEmpty) {
    add(
      'Review the changes',
      'Review the changes in ${files.join(', ')}. Look for edge cases, '
          'unused code and regressions, then fix anything you find.',
    );
    add(
      'Run the relevant checks',
      'Run the relevant checks for the changes in ${files.join(', ')} and fix '
          'any failures. Do not skip a failing check.',
    );
  }

  switch (project.kind) {
    case ProjectKind.web:
      add(
        'Check the interface',
        'Check the visible interface for small screens, long text and empty '
            'states. Fix any layout or accessibility problems you find.',
      );
      break;
    case ProjectKind.flutter:
      add(
        'Check the Flutter build',
        'Run the Flutter analyzer and tests for this project, then fix any '
            'failures they report.',
      );
      break;
    case ProjectKind.node:
      add(
        'Check the Node build',
        'Run the install and build scripts for this project, then fix any '
            'errors or warnings they report.',
      );
      break;
    case ProjectKind.python:
      add(
        'Run the Python checks',
        'Run the project entry point and any tests, then fix the first real '
            'failure you find.',
      );
      break;
    case ProjectKind.php:
      add(
        'Run the PHP checks',
        'Run the PHP entry point and any tests, then fix the first real failure '
            'you find.',
      );
      break;
    case ProjectKind.go:
      add(
        'Run the Go checks',
        'Run go test ./... and go vet ./..., then fix any failures.',
      );
      break;
    case ProjectKind.blank:
      break;
  }

  final lastAssistant = thread.lastWhere(
    (entry) => entry.role == ChatRole.assistant,
    orElse: () => ChatEntry(
      id: '',
      role: ChatRole.note,
      text: '',
      at: DateTime.now(),
    ),
  );
  final answer = lastAssistant.text.toLowerCase();
  if (answer.contains('test') || answer.contains('fail')) {
    add(
      'Lock in the fix with a test',
      'Add a focused regression test for the behavior just changed, then run '
          'it and show the result.',
    );
  }
  if (canPush && files.isNotEmpty) {
    add(
      'Commit the result',
      'Review the diff and commit the current changes with a clear message.',
    );
  }
  if (suggestions.length < 3) {
    add(
      'Explain how to verify it',
      'Summarize what changed and give the exact steps I should use to verify '
          'it on this device.',
    );
  }
  return suggestions.take(3).toList();
}
