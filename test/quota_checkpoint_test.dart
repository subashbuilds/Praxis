import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/quota_tracker.dart';
import 'package:praxis/core/task_checkpoint.dart';
import 'package:praxis/models.dart';

void main() {
  ProviderConfig provider({
    required String id,
    ApiFlavor flavor = ApiFlavor.openai,
    int dailyLimit = 0,
  }) =>
      ProviderConfig(
        id: id,
        name: id,
        icon: 'asset.svg',
        baseUrl: 'https://example.test/v1',
        model: 'model',
        flavor: flavor,
        keys: const ['test-key'],
        dailyLimit: dailyLimit,
      );

  TaskCheckpoint checkpoint({TaskCheckpointStatus? status}) => TaskCheckpoint(
        taskId: 'task-1',
        projectId: 'project-1',
        providerId: 'openai',
        providerName: 'OpenAI',
        model: 'model',
        originalPrompt: 'Build the page',
        createdAt: DateTime.utc(2026, 11, 9, 10),
        updatedAt: DateTime.utc(2026, 11, 9, 10, 5),
        status: status ?? TaskCheckpointStatus.resumable,
        completed: const ['Wrote index.html'],
        pendingStep: 'Style the hero',
        changedFiles: const {'index.html': 'digest'},
      );

  group('quota tracker', () {
    test('counts per provider and resets at local midnight', () {
      var now = DateTime(2026, 11, 9, 23, 59);
      final tracker = QuotaTracker(clock: () => now);
      tracker.record('openai');
      tracker.record('openai');
      tracker.record('anthropic');
      expect(tracker.usedToday('openai'), 2);
      expect(tracker.usedToday('anthropic'), 1);

      now = DateTime(2026, 11, 10, 0, 0);
      expect(tracker.usedToday('openai'), 0);
      expect(tracker.usedToday('anthropic'), 0);
    });

    test('uses the user limit and warns at 80%, low, and exhausted', () {
      final tracker = QuotaTracker(clock: () => DateTime(2026, 11, 9, 12));
      final config = provider(id: 'openai', dailyLimit: 10);
      for (var i = 0; i < 7; i++) {
        tracker.record('openai');
      }
      expect(tracker.status(config).warning, isFalse);
      tracker.record('openai');
      expect(tracker.status(config).warning, isTrue);
      expect(tracker.status(config).low, isTrue);
      tracker.record('openai');
      tracker.record('openai');
      expect(tracker.status(config).exhausted, isTrue);
      expect(tracker.status(config).remaining, 0);
      expect(tracker.status(config).label, '10/10 requests used today');
    });

    test('persists counts through JSON', () {
      var now = DateTime(2026, 11, 9, 12);
      final tracker = QuotaTracker(clock: () => now);
      tracker.record('openai');
      final restored =
          QuotaTracker.fromJson(tracker.toJson(), clock: () => now);
      expect(restored.usedToday('openai'), 1);
    });

    test('provider daily limit survives JSON', () {
      final config = provider(id: 'openai', dailyLimit: 42);
      final restored = ProviderConfig.fromJson(config.toJson());
      expect(restored.dailyLimit, 42);
    });
  });

  group('quota mapping', () {
    test('maps 429 and Retry-After for both API adapters', () async {
      final client = AiClient(
        client: MockClient((_) async => http.Response(
              '{"error":{"message":"insufficient_quota"}}',
              429,
              headers: {
                'retry-after': '30',
                'content-type': 'application/json'
              },
            )),
      );
      for (final flavor in [ApiFlavor.openai, ApiFlavor.anthropic]) {
        await expectLater(
          client.complete(
            provider: provider(id: 'adapter', flavor: flavor),
            system: '',
            turns: const [],
            tools: const [],
          ),
          throwsA(isA<QuotaExceeded>()
              .having((error) => error.status, 'status', 429)
              .having((error) => error.retryAfter, 'retryAfter',
                  const Duration(seconds: 30))),
        );
      }
    });

    test('maps a 402 credit response to QuotaExceeded', () async {
      final client = AiClient(
        client: MockClient((_) async => http.Response(
              '{"error":{"message":"account is out of credit"}}',
              402,
              headers: {'content-type': 'application/json'},
            )),
      );
      await expectLater(
        client.complete(
          provider: provider(id: 'billing'),
          system: '',
          turns: const [],
          tools: const [],
        ),
        throwsA(isA<QuotaExceeded>()),
      );
    });
  });

  group('task checkpoint', () {
    test('round-trips a resumable checkpoint without file contents', () {
      final original = checkpoint();
      final restored = TaskCheckpoint.fromJson(original.toJson())!;
      expect(restored.resumable, isTrue);
      expect(restored.completed, ['Wrote index.html']);
      expect(restored.pendingStep, 'Style the hero');
      expect(restored.changedFiles, {'index.html': 'digest'});
    });

    test('deduplicates completed actions by fingerprint', () {
      final args = {'path': 'index.html', 'content': 'hello'};
      final fingerprint = TaskCheckpoint.actionFingerprint('write_file', args);
      final action = CheckpointAction(
        fingerprint: fingerprint,
        tool: 'write_file',
        label: 'Wrote index.html',
      );
      final once = checkpoint().withAction(action);
      final twice = once.withAction(action);
      expect(once.completedActions, hasLength(1));
      expect(twice.completedActions, hasLength(1));
      expect(
        TaskCheckpoint.actionFingerprint('write_file', args),
        fingerprint,
      );
      expect(
        TaskCheckpoint.actionFingerprint(
          'write_file',
          const {'path': 'index.html', 'content': 'different'},
        ),
        isNot(fingerprint),
      );
    });

    test('redacts credentials before a checkpoint is written', () {
      final clean = TaskCheckpoint.sanitize(
        'key sk-abcdefghijklmnop token=super-secret',
      );
      expect(clean, isNot(contains('super-secret')));
      expect(clean, isNot(contains('sk-abcdefghijklmnop')));
    });

    test('restores resumable state from the file store', () async {
      final directory =
          await Directory.systemTemp.createTemp('praxis_checkpoints_');
      addTearDown(() => directory.delete(recursive: true));
      final store = FileTaskCheckpointStore(directory);
      await store.prepare();
      await store.save(checkpoint());
      final latest = await store.latestFor('project-1');
      expect(latest?.pendingStep, 'Style the hero');
      await store.remove('task-1');
      expect(await store.latestFor('project-1'), isNull);
    });
  });
}
