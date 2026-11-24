/// What the loop should do with a model reply that carried no tool calls.
///
/// The classifier is pure so every transition can be tested without a
/// provider, a clock or a project folder. The loop keeps one switch over these
/// values instead of a chain of independent `if` statements.
enum ReplyOutcome {
  /// A finished answer with nothing left to do.
  finalAnswer,

  /// The reply describes the next step and stops without running it.
  unfinishedAnnouncement,

  /// The model output budget cut the reply off.
  outputLimit,

  /// The stream ended before a terminator arrived.
  truncatedStream,

  /// The provider reported a protocol failure instead of an answer.
  protocolError,

  /// Nothing usable was returned.
  emptyReply,

  /// The model stopped while checklist steps are still open.
  openChecklist,
}

class ReplyClassifier {
  /// Transition table, in priority order:
  ///
  /// | result                  | loop action                                   |
  /// |-------------------------|-----------------------------------------------|
  /// | truncatedStream         | transient retry, never shown as an answer     |
  /// | outputLimit             | nudge to continue, then pause                 |
  /// | emptyReply              | pause with a Continue action                  |
  /// | protocolError           | retry once, then pause                        |
  /// | unfinishedAnnouncement  | commit the text, nudge, then pause at the cap |
  /// | openChecklist           | nudge to finish the next step                 |
  /// | finalAnswer             | completed                                     |
  static ReplyOutcome classify({
    required String text,
    bool hitOutputLimit = false,
    bool truncated = false,
    bool answerOnly = false,
    bool planMode = false,
    bool actExpected = false,
    int openSteps = 0,
  }) {
    if (truncated) return ReplyOutcome.truncatedStream;
    if (hitOutputLimit) return ReplyOutcome.outputLimit;
    if (text.trim().isEmpty) return ReplyOutcome.emptyReply;
    if (answerOnly || planMode) return ReplyOutcome.finalAnswer;
    if (actExpected && announcesAction(text)) {
      return ReplyOutcome.unfinishedAnnouncement;
    }
    if (openSteps > 0) return ReplyOutcome.openChecklist;
    return ReplyOutcome.finalAnswer;
  }

  /// True when the last sentence of a reply describes an action the model
  /// meant to take in that same turn.
  ///
  /// Only the last sentence counts: a complete answer may open with "I'll
  /// explain…" and still finish. Past-tense summaries, questions and closings
  /// such as "let me know" are answers, not announcements.
  static bool announcesAction(String reply) {
    final normalized = normalize(reply);
    if (normalized.isEmpty) return false;
    final sentences = normalized.split(RegExp(r'(?<=[.!?])\s+'));
    var tail = sentences.last.trim();
    if (tail.isEmpty) return false;
    // A question to the user is a finished turn.
    if (tail.endsWith('?')) return false;
    // A closing offer is a finished answer.
    if (RegExp(r'\blet me know\b', caseSensitive: false).hasMatch(tail)) {
      return false;
    }

    final original = tail.toLowerCase();
    var lower = original;
    for (var guard = 0; guard < 4; guard++) {
      final stripped = lower.replaceFirst(
        RegExp(
            r'^(?:and|so|now|next|then|first|finally|ok|okay|alright)[,]?\s+'),
        '',
      );
      if (stripped == lower) break;
      lower = stripped;
    }

    final gerund = _gerundAtStart(original) || _gerundAtStart(lower);
    final intent = _hasFirstPersonIntent(original) ||
        _hasFirstPersonIntent(lower) ||
        RegExp(r'^next[,:]').hasMatch(original) ||
        RegExp(r'^next up').hasMatch(original);
    final openEnded = RegExp(r'(:|\.\.\.|…)$').hasMatch(tail);
    if (!gerund && !intent && !openEnded) return false;
    if (!_hasActionVerb(original) && !_hasActionVerb(lower)) return false;
    return true;
  }

  static String normalize(String raw) {
    var text = raw
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('`', ' ')
        .replaceAll(RegExp(r'\*+|#+'), ' ');
    text = text.replaceAll(
      RegExp(r'\blet me know\b.*$', caseSensitive: false, dotAll: true),
      ' ',
    );
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _hasFirstPersonIntent(String lower) {
    const intents = [
      'let me ',
      "let's ",
      'let us ',
      "i'll ",
      'i will ',
      "i'm going to ",
      'i am going to ',
      'i need to ',
      'i should ',
      'going to ',
      'time to ',
      'next up',
      'next i ',
    ];
    return intents.any(lower.startsWith);
  }

  static bool _gerundAtStart(String lower) => _gerunds.any(
        (word) => lower.startsWith('$word '),
      );

  static const _gerunds = {
    'reading',
    'checking',
    'writing',
    'editing',
    'updating',
    'verifying',
    'testing',
    'building',
    'fixing',
    'reviewing',
    'examining',
    'creating',
    'adding',
    'installing',
    'committing',
    'deploying',
    'rerunning',
    'validating',
    'compiling',
    'linting',
    'applying',
    'patching',
    'searching',
    'listing',
    'fetching',
    'wiring',
    'cleaning',
    'removing',
    'deleting',
    'renaming',
    'moving',
    'implementing',
    'refactoring',
    'formatting',
    'analyzing',
    'looking',
    'inspecting',
    'parsing',
    'rendering',
    'reloading',
    'pushing',
    'saving',
    'copying',
    'generating',
    'configuring',
    'running',
    'opening',
    'confirming',
    'scanning',
    'downloading',
    'uploading',
  };

  static final _verbs = RegExp(
    r'\b(read|open|check|inspect|look|search|list|run|write|edit|update|'
    r'verify|grep|find|fetch|test|build|fix|review|examine|create|add|'
    r'install|commit|deploy|rerun|confirm|validate|compile|lint|apply|'
    r'patch|remove|delete|rename|move|implement|refactor|format|analyze|'
    r'wire|clean|migrate|generate|start|stop|restart|connect|download|'
    r'upload|scan|parse|render|reload|push|save|copy|set|configure)\b',
  );

  static bool _hasActionVerb(String lower) =>
      _verbs.hasMatch(lower) || _hasGerundWord(lower);

  static bool _hasGerundWord(String lower) => _gerunds.any(
        (word) => RegExp('\\b$word\\b').hasMatch(lower),
      );
}
