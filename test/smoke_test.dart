import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polydev/app.dart';

void main() {
  testWidgets('home → new project → tabs → shell → preview', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PolyDevApp());
    await tester.pumpAndSettle();

    expect(find.text('Your workbench.'), findsOneWidget);
    expect(find.text('polydev-web'), findsOneWidget);

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    expect(find.text('Create project'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'ember-mobile');
    await tester.pump();
    await tester.tap(find.text('Create project'));
    await tester.pumpAndSettle();

    expect(find.text('ember-mobile'), findsOneWidget);

    await tester.tap(find.text('Shell'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'pwd');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(find.textContaining('/files/home/projects/polydev-web'),
        findsOneWidget);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('localhost:5173'), findsOneWidget);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('EXPLORER'), findsOneWidget);
  });
}
