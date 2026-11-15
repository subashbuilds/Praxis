import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/background_jobs.dart';
import 'package:praxis/core/store.dart';

void main() {
  test('running jobs are kept and marked interrupted after a restart',
      () async {
    final store = MemoryStore();
    final journal = BackgroundJobJournal(store);
    final started = DateTime(2026, 11, 15, 10, 30);
    journal.upsert(BackgroundJobRecord(
      id: 'agent-1',
      projectId: 'demo',
      projectName: 'Demo',
      kind: BackgroundJobKind.agent,
      title: 'Agent task',
      detail: 'Working with Example',
      startedAt: started,
      updatedAt: started,
    ));
    await journal.flush();

    final restored = BackgroundJobJournal(store);
    await restored.load();

    expect(restored.items, hasLength(1));
    expect(restored.items.single.status, BackgroundJobStatus.interrupted);
    expect(restored.items.single.running, isFalse);
    expect(restored.items.single.detail, contains('closed before'));
    expect(restored.items.single.data, isEmpty);
  });

  test('finished jobs can be cleared without deleting the active one',
      () async {
    final journal = BackgroundJobJournal(MemoryStore());
    final now = DateTime(2026, 11, 15);
    journal.upsert(BackgroundJobRecord(
      id: 'done',
      projectId: 'demo',
      projectName: 'Demo',
      kind: BackgroundJobKind.deploy,
      title: 'Deploy',
      status: BackgroundJobStatus.completed,
      startedAt: now,
      updatedAt: now,
    ));
    journal.upsert(BackgroundJobRecord(
      id: 'active',
      projectId: 'demo',
      projectName: 'Demo',
      kind: BackgroundJobKind.agent,
      title: 'Agent task',
      startedAt: now.add(const Duration(seconds: 1)),
      updatedAt: now.add(const Duration(seconds: 1)),
    ));

    journal.clearFinished();

    expect(journal.items.map((job) => job.id), ['active']);
  });
}
