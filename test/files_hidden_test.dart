import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';
import 'package:praxis/workspace/files_tab.dart';

void main() {
  testWidgets('hidden folders expand to show their children', (tester) async {
    late Directory temp;
    late AppState state;
    late Project project;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('praxis_hidden_files_');
      state = AppState(
        root: temp,
        store: MemoryStore(),
        seedWelcome: false,
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
      await state.init();
      project = await state.createProject(
        'hidden-files',
        ProjectKind.blank,
        persistChat: false,
      );
      await state
          .fsFor(project)
          .write('.github/workflows/ci.yml', 'name: CI\n');
    });
    addTearDown(() async {
      state.dispose();
      await temp.delete(recursive: true);
    });

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: Scaffold(body: FilesTab(project: project)),
        ),
      ),
    );
    Future<void> settleIo() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }
    }

    await settleIo();
    expect(find.text('.github'), findsOneWidget);
    await tester.tap(find.text('.github'));
    await settleIo();

    expect(find.text('workflows'), findsOneWidget);
    await tester.tap(find.text('workflows'));
    await settleIo();

    expect(find.text('ci.yml'), findsOneWidget);
    // Let the delayed change-badge scan finish before the test tree is torn
    // down, otherwise the fake-async timer remains pending.
    await tester.pump(const Duration(seconds: 1));
  });
}
