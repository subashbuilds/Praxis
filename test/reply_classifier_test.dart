import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/reply_classifier.dart';

void main() {
  group('announcement detection', () {
    const positives = [
      'Let me read the file.',
      'Let me check the tests.',
      'Let me write the parser now.',
      'Let’s run the build.',
      "Let's verify the output.",
      "I'll update the README.",
      'I’ll fix the failing test.',
      'I will inspect the config.',
      "I'm going to add a guard clause.",
      'I am going to run the suite.',
      'I need to search for the symbol.',
      'I should check the logs.',
      "Now I'll apply the patch.",
      "Next, I'll edit the workflow.",
      'Next I will rerun the tests.',
      'Next up: wiring the deploy step.',
      'Time to run flutter analyze.',
      "First, I'll grep for the handler.",
      "Then I'll compile the project.",
      'Running the tests...',
      'Now verifying the build.',
      'Checking the output now.',
      'Reading the manifest.',
      'Writing the patch...',
      'Reviewing the diff now.',
      'Examining the stack trace.',
      'Creating the new screen.',
      'Adding the route.',
      'Installing the dependency.',
      'Committing the changes.',
      'Deploying the worker.',
      'Rerunning the failing test.',
      'Validating the schema.',
      'Compiling the app.',
      'Linting the package.',
      'Let me examine the config file.',
      'Let me create the missing folder.',
      'Let me install the package.',
      "I'll commit and push the fix.",
      'Next: patch the loader.',
      'Let me look at the logs.',
      'Let me fetch the schema.',
      'Now I need to confirm the exit code.',
      'Let me confirm the build passes.',
      "I'm going to clean the cache.",
      '**Let me read** the file.',
      'Let me\nread the file.',
      'OK, let me run the tests.',
      'Finally, I’ll review the diff.',
      'So I need to update the route.',
    ];

    const negatives = [
      'Done. I updated the README and ran the tests, all pass.',
      'Let me know if you want me to run the tests.',
      'I will leave that to you.',
      'The tests pass. Would you like me to run the build?',
      'I updated the config and verified the output.',
      'The build ran and all checks passed.',
      "Let me know when you're ready.",
      'I should mention that this file is generated.',
      "This approach is simpler. I'll note it in the summary.",
      'Done: files changed, tests pass, build green.',
      'I ran the tests and they pass.',
      'The parser reads the file and writes the output.',
      'I checked the logs; there were no errors.',
      "Here's what changed: the route, the screen and the test.",
      'Let me explain how the loop works.',
      "I'll leave the decision to you.",
      'Can you confirm the branch name?',
      'I fixed the bug. Let me know if anything else fails.',
      'The command ran successfully.',
      'I updated the dependency version.',
      'We should keep the current behavior.',
      'The output was verified against the schema.',
      "I've reviewed the diff; it looks correct.",
      'No changes were needed.',
      'Next steps are documented in the README.',
      'I will note that the tests pass.',
      "Let me know if you'd like a different approach.",
      'The new test verifies the checklist.',
      'All tests pass and the build is green.',
    ];

    test('recognises announcements in the last sentence', () {
      final missed = [
        for (final phrase in positives)
          if (!ReplyClassifier.announcesAction(phrase)) phrase,
      ];
      expect(missed, isEmpty);
    });

    test('keeps finished answers out of the nudge path', () {
      final falsePositives = [
        for (final phrase in negatives)
          if (ReplyClassifier.announcesAction(phrase)) phrase,
      ];
      expect(falsePositives, isEmpty);
    });

    test('curly apostrophes and markdown do not hide an announcement', () {
      expect(
          ReplyClassifier.announcesAction('I’ll **write** the file.'), isTrue);
      expect(
        ReplyClassifier.announcesAction('Let me\n`read` the file.'),
        isTrue,
      );
    });
  });

  group('reply classification', () {
    test('a truncated stream is never a final answer', () {
      expect(
        ReplyClassifier.classify(text: 'Partial', truncated: true),
        ReplyOutcome.truncatedStream,
      );
    });

    test('an announcement with an expected action is unfinished', () {
      expect(
        ReplyClassifier.classify(
          text: 'Let me run the tests.',
          actExpected: true,
        ),
        ReplyOutcome.unfinishedAnnouncement,
      );
    });

    test('answer-only replies are final even with an announcement', () {
      expect(
        ReplyClassifier.classify(
          text: 'Let me explain how it works.',
          actExpected: true,
          answerOnly: true,
        ),
        ReplyOutcome.finalAnswer,
      );
    });

    test('open checklist steps are reported before completion', () {
      expect(
        ReplyClassifier.classify(text: 'Finished.', openSteps: 2),
        ReplyOutcome.openChecklist,
      );
    });

    test('an empty reply is not a completed answer', () {
      expect(
        ReplyClassifier.classify(text: '   '),
        ReplyOutcome.emptyReply,
      );
    });
  });
}
