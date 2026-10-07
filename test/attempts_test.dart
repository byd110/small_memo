import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:small_memo/main.dart';
import 'package:small_memo/task.dart';
import 'package:small_memo/task_controller.dart';
import 'package:small_memo/task_store.dart';
import 'widget_test.dart' show MemoryStore;

void main() {
  test(
    'edit, completion and removal preserve other stamps and identity',
    () async {
      final now = DateTime.utc(2026, 10, 7, 15, 30);
      final controller = TaskController(MemoryStore(), now: () => now);
      await controller.load();
      await controller.add('Read');
      final id = controller.tasks.single.id;
      await controller.recordAttempt(id);
      await controller.recordAttempt(id);
      final stamps = controller.tasks.single.attempts;
      expect(stamps.map((a) => a.id).toSet(), hasLength(2));
      expect(stamps.first.at, now);
      await controller.toggle(id);
      await controller.edit(id, '  Read a chapter  ');
      final task = controller.tasks.single;
      expect(task.id, id);
      expect(task.title, 'Read a chapter');
      expect(task.done, isTrue);
      expect(task.attempts, stamps);
      await controller.removeAttempt(id, stamps.first.id);
      expect(controller.tasks.single.attempts.single.id, stamps.last.id);
      expect(await controller.edit(id, '  '), isFalse);
      expect(await controller.recordAttempt('missing'), isFalse);
    },
  );

  test('failed stamps and edits do not mutate saved state', () async {
    final store = MemoryStore();
    final controller = TaskController(store);
    await controller.load();
    await controller.add('Read');
    final id = controller.tasks.single.id;
    store.fail = true;
    expect(await controller.recordAttempt(id), isFalse);
    expect(await controller.edit(id, 'Changed'), isFalse);
    expect(controller.tasks.single.title, 'Read');
    expect(controller.tasks.single.attempts, isEmpty);
  });

  test('date ranges include start and exclude next-day midnight', () {
    final start = DateTime(2026, 10, 7);
    final end = DateTime(2026, 10, 8);
    final task = Task(
      id: '1',
      title: 'Read',
      done: true,
      attempts: [
        Attempt(
          id: 'a',
          at: start.subtract(const Duration(microseconds: 1)).toUtc(),
        ),
        Attempt(id: 'b', at: start.toUtc()),
        Attempt(
          id: 'c',
          at: end.subtract(const Duration(microseconds: 1)).toUtc(),
        ),
        Attempt(id: 'd', at: end.toUtc()),
      ],
    );
    expect(task.attemptsBetween(start, end), 2);
    expect(task.attemptsBetween(null, null), 4);
    expect(task.attemptsBetween(end, end), 0);
  });

  test(
    'legacy tasks upgrade with backup; edited history survives reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('memo_migration_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/tasks.json');
      const original =
          '{"version":1,"tasks":[{"id":"old","title":"Old","done":true}]}';
      await file.writeAsString(original);
      final store = FileTaskStore(file);
      final controller = TaskController(
        store,
        now: () => DateTime.utc(2026, 10, 7),
      );
      await controller.load();
      expect(controller.tasks.single.attempts, isEmpty);
      await controller.recordAttempt('old');
      await controller.edit('old', 'New');
      await store.close();
      expect(await File('${file.path}.v1.bak').readAsString(), original);
      expect(jsonDecode(await file.readAsString())['version'], 2);
      final reopened = FileTaskStore(file);
      final saved = (await reopened.load()).single;
      expect(saved.title, 'New');
      expect(saved.done, isTrue);
      expect(saved.id, 'old');
      expect(saved.attempts.single.at, DateTime.utc(2026, 10, 7));
      await reopened.close();
    },
  );

  test('corrupt v2 history is rejected without overwriting it', () async {
    final dir = await Directory.systemTemp.createTemp('memo_corrupt_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/tasks.json');
    final store = FileTaskStore(file);
    for (final attempts in [
      null,
      [
        {'id': 'a', 'at': 'not-a-date'},
      ],
      [
        {'id': 'a', 'at': '2026-02-31T00:00:00.000Z'},
      ],
      [
        {'id': 'a', 'at': '2026-10-07T00:00:00.000Z'},
        {'id': 'a', 'at': '2026-10-07T00:00:00.000Z'},
      ],
    ]) {
      final content = jsonEncode({
        'version': 2,
        'tasks': [
          {'id': 't', 'title': 'Read', 'done': false, 'attempts': attempts},
        ],
      });
      await file.writeAsString(content);
      await expectLater(store.load(), throwsFormatException);
      await expectLater(store.save([]), throwsStateError);
      expect(await file.readAsString(), content);
    }
    await store.close();
  });

  testWidgets(
    'summary presets include completed tasks and custom cancel preserves period',
    (tester) async {
      final today = DateTime.now();
      var clock = today.subtract(const Duration(days: 40));
      final controller = TaskController(MemoryStore(), now: () => clock);
      await controller.load();
      await controller.add('Practice');
      final id = controller.tasks.single.id;
      await controller.recordAttempt(id);
      clock = today.subtract(const Duration(days: 2));
      await controller.recordAttempt(id);
      clock = today;
      await controller.recordAttempt(id);
      await controller.toggle(id);
      await tester.pumpWidget(MemoApp(controller: controller));
      await tester.tap(find.byTooltip('Attempt summary'));
      await tester.pumpAndSettle();
      expect(find.text('2 attempts total'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today').last);
      await tester.pumpAndSettle();
      expect(find.text('1 attempt total'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All time').last);
      await tester.pumpAndSettle();
      expect(find.text('3 attempts total'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom dates…').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        'all',
      );
      expect(find.text('3 attempts total'), findsOneWidget);
    },
  );

  testWidgets('log, edit, history removal and summary work together', (
    tester,
  ) async {
    final controller = TaskController(MemoryStore());
    await controller.load();
    await controller.add('Practice');
    await tester.pumpWidget(MemoApp(controller: controller));
    await tester.tap(find.text('Log attempt'));
    await tester.pumpAndSettle();
    expect(find.text('1 attempt'), findsOneWidget);
    await tester.tap(find.byTooltip('Task options for Practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit description'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Practice'),
      'Practice piano',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.tasks.single.title, 'Practice piano');
    expect(controller.tasks.single.attempts, hasLength(1));
    await tester.tap(find.byTooltip('Attempt summary'));
    await tester.pumpAndSettle();
    expect(find.text('1 attempt total'), findsOneWidget);
    expect(find.text('Practice piano'), findsOneWidget);
    await tester.tap(find.text('Practice piano'));
    await tester.pumpAndSettle();
    expect(find.text('Attempt history'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove attempt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('No attempts yet.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('0 attempts total'), findsOneWidget);
  });

  testWidgets('editing failure keeps draft and history; small screen fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    final controller = TaskController(store);
    await controller.load();
    await controller.add('Practice');
    await controller.recordAttempt(controller.tasks.single.id);
    await tester.pumpWidget(MemoApp(controller: controller));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Task options for Practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit description'));
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.enterText(find.widgetWithText(TextField, 'Practice'), 'Draft');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Draft'), findsOneWidget);
    expect(find.textContaining('Could not save. Your changes'), findsOneWidget);
    expect(controller.tasks.single.title, 'Practice');
    expect(controller.tasks.single.attempts, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
