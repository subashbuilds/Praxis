import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/integrations.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/core/task_checkpoint.dart';
import 'package:praxis/core/usage.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';

void main() {
  test('sending continue resumes a paused checkpoint instead of restarting',
      () async {
    final temp = await Directory.systemTemp.createTemp('praxis_resume_');
    addTearDown(() => temp.delete(recursive: true));
    final store = MemoryStore();
    final checkpoints = MemoryTaskCheckpointStore();

    final setup = AppState(
      root: temp,
      store: store,
      checkpointStore: checkpoints,
      seedWelcome: false,
    );
    await setup.init();
    final project = await setup.createProject('resume', ProjectKind.blank);
    setup.dispose();

    final checkpoint = TaskCheckpoint(
      taskId: 'round-limit-task',
      projectId: project.id,
      providerId: 'test',
      providerName: 'Test',
      model: 'test-model',
      originalPrompt: 'Implement the saved feature.',
      createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      updatedAt: DateTime.now(),
      status: TaskCheckpointStatus.resumable,
      completed: const ['created lib/main.dart'],
      pendingStep:
          'Continue the original request from the last completed step.',
      lastError: 'Paused after 40 tool rounds.',
      changedFiles: const {'lib/main.dart': 'digest'},
    );
    await checkpoints.save(checkpoint);

    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requests.add(
        (jsonDecode(request.body) as Map).cast<String, dynamic>(),
      );
      final first = requests.length == 1;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': first
                  ? {
                      'role': 'assistant',
                      'content': '',
                      'tool_calls': [
                        {
                          'id': 'call_resume',
                          'type': 'function',
                          'function': {
                            'name': 'write_file',
                            'arguments': jsonEncode({
                              'path': 'resumed.txt',
                              'content': 'continued',
                            }),
                          },
                        },
                      ],
                    }
                  : {
                      'role': 'assistant',
                      'content': 'Resumed and finished the remaining step.',
                    },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final state = AppState(
      root: temp,
      store: store,
      checkpointStore: checkpoints,
      seedWelcome: false,
      httpClient: client,
    );
    addTearDown(state.dispose);
    await state.init();
    await state.saveProvider(const ProviderConfig(
      id: 'test',
      name: 'Test',
      icon: 'x',
      baseUrl: 'https://example.test/v1',
      model: 'test-model',
      flavor: ApiFlavor.openai,
      keys: ['key'],
    ));

    expect(state.hasResumableCheckpoint(project.id), isTrue);
    await state.send(project.id, 'continue');

    expect(requests, isNotEmpty);
    final firstMessages = (requests.first['messages'] as List)
        .whereType<Map>()
        .where((message) => message['role'] == 'user')
        .map((message) => '${message['content']}')
        .toList();
    expect(firstMessages, isNotEmpty);
    expect(firstMessages.first, contains('RESUME TASK'));
    expect(firstMessages.first, contains('Implement the saved feature.'));
    expect(firstMessages.first, isNot(equals('continue')));

    expect(await state.fsFor(project).read('resumed.txt'), 'continued');
    expect(state.checkpointFor(project.id)?.taskId, 'round-limit-task');
    expect(
      state.threadOf(project.id).any(
            (entry) => entry.text.contains('Resumed with'),
          ),
      isTrue,
    );
  });

  test('a deploy job and its progress remain after the caller detaches',
      () async {
    final temp = await Directory.systemTemp.createTemp('praxis_deploy_job_');
    addTearDown(() => temp.delete(recursive: true));
    final state = AppState(
      root: temp,
      store: MemoryStore(),
      seedWelcome: false,
    );
    addTearDown(state.dispose);
    await state.init();
    final project = await state.createProject('deploy', ProjectKind.web);

    final gate = Completer<void>();
    final job = DeployJob(
      platform: IntegrationKind.vercel,
      runtime: 'Vercel',
    );
    final start = state.startDeploy(
      project.id,
      job,
      (onProgress) async {
        onProgress(
          const DeployProgress('Uploading', detail: 'half the files'),
        );
        await gate.future;
        return const IntegrationResult(
          message: 'Deployed after the sheet closed.',
          runtime: 'Vercel',
        );
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(state.deployJobFor(project.id)?.running, isTrue);
    expect(
      state.deployJobFor(project.id)?.progress?.detail,
      'half the files',
    );

    gate.complete();
    await start;
    expect(job.running, isFalse);
    expect(
      state.deployJobFor(project.id)?.result?.message,
      'Deployed after the sheet closed.',
    );
  });

  test('context usage reads the latest matching request', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_context_');
    addTearDown(() => temp.delete(recursive: true));
    final state = AppState(
      root: temp,
      store: MemoryStore(),
      seedWelcome: false,
    );
    addTearDown(state.dispose);
    await state.init();
    final project = await state.createProject('context', ProjectKind.blank);

    final older = DateTime.now().subtract(const Duration(minutes: 5));
    state.usageEvents.add(UsageEvent(
      at: older,
      projectId: project.id,
      providerId: 'test',
      providerName: 'Test',
      keyIndex: 0,
      model: 'test-model',
      promptTokens: 66000,
      completionTokens: 200,
    ));
    state.usageEvents.add(UsageEvent(
      at: DateTime.now(),
      projectId: project.id,
      providerId: 'test',
      providerName: 'Test',
      keyIndex: 0,
      model: 'test-model',
      promptTokens: 128000,
      completionTokens: 500,
    ));

    expect(
      state.contextUsedFor('test', 'test-model', projectId: project.id),
      128000,
    );
  });
}
