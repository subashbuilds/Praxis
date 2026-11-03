/// One entry in an agent thread. The shapes mirror what the shipped app
/// shows: prose, a command run, and a file edit.
sealed class ChatItem {
  const ChatItem();
}

class UserNote extends ChatItem {
  const UserNote(this.text);
  final String text;
}

class AgentNote extends ChatItem {
  const AgentNote(this.text);
  final String text;
}

enum ToolState { running, passed, failed }

class CommandRun extends ChatItem {
  const CommandRun({
    required this.command,
    required this.output,
    this.state = ToolState.passed,
  });

  final String command;
  final String output;
  final ToolState state;
}

class FileEdit extends ChatItem {
  const FileEdit({
    required this.path,
    required this.added,
    required this.removed,
    required this.diff,
  });

  final String path;
  final int added;
  final int removed;

  /// Lines are already prefixed with '+' / '-' / ' '.
  final List<String> diff;
}
