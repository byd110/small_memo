import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:small_memo/main.dart';
import 'package:small_memo/priority_views.dart';
import 'package:small_memo/sync_store.dart';
import 'package:small_memo/task.dart';
import 'package:small_memo/task_controller.dart';
import 'package:small_memo/task_store.dart';

class MemoryStore implements TaskStore {
  MemoryStore(this.tasks);
  List<Task> tasks;
  bool fail = false;
  @override
  Future<List<Task>> load() async => tasks;
  @override
  Future<void> save(List<Task> next) async {
    if (fail) throw const FileSystemException('Disk full');
    tasks = next;
  }
}

void main() {
  test(
    'numeric grouping, manual ordering, and history survive all task edits',
    () async {
      final attempt = Attempt(id: 'stamp', at: DateTime.utc(2026, 10, 24));
      final controller = TaskController(
        MemoryStore([
          const Task(id: 'ten', title: 'Ten', priority: 10),
          Task(id: 'one', title: 'One', priority: 1, attempts: [attempt]),
          const Task(id: 'u', title: 'Unclassified'),
          const Task(id: 'two', title: 'Two', priority: 2),
        ]),
      );
      await controller.load();
      expect(controller.tasks.map((t) => t.id), ['u', 'one', 'two', 'ten']);
      await controller.move('ten', 1, beforeId: 'one');
      expect(controller.tasks.map((t) => t.id), ['u', 'ten', 'one', 'two']);
      await controller.setPriority('one', null);
      await controller.edit('one', 'Edited');
      await controller.toggle('one');
      final task = controller.tasks[1];
      expect(task.id, 'one');
      expect(task.priority, isNull);
      expect(task.done, isTrue);
      expect(task.attempts.single.id, 'stamp');
      await controller.recordAttempt('one');
      expect(controller.tasks[1].attempts, hasLength(2));
      await controller.add('New');
      expect(
        controller.tasks.where((t) => t.priority == null).last.title,
        'New',
      );
      expect(await controller.setPriority('one', 0), false);
      expect(await controller.setPriority('one', -1), false);
      expect(await controller.setPriority('one', 2147483648), false);
      expect(await controller.move('one', 1, beforeId: 'missing'), false);
    },
  );

  test('failed move keeps the previous order and priority', () async {
    final store = MemoryStore([
      const Task(id: 'a', title: 'A'),
      const Task(id: 'b', title: 'B', position: 1),
    ]);
    final c = TaskController(store);
    await c.load();
    store.fail = true;
    expect(await c.move('b', 1), false);
    expect(c.tasks.map((t) => t.id), ['a', 'b']);
    expect(c.tasks.every((t) => t.priority == null), true);
  });

  test(
    'v2 migration preserves list order, backs up, and reopens v4 placement',
    () async {
      final dir = await Directory.systemTemp.createTemp('memo_priority_');
      final file = File('${dir.path}/tasks.json');
      final original = jsonEncode({
        'version': 2,
        'tasks': [
          {'id': 'z', 'title': 'First', 'done': true, 'attempts': []},
          {'id': 'a', 'title': 'Second', 'done': false, 'attempts': []},
        ],
      });
      await file.writeAsString(original);
      final store = FileTaskStore(file);
      final controller = TaskController(store);
      await controller.load();
      expect(controller.tasks.map((t) => t.id), ['z', 'a']);
      await controller.setPriority('a', 1);
      expect(await File('${file.path}.v2.bak').readAsString(), original);
      await store.close();
      final reopened = FileTaskStore(file);
      final loaded = orderedTasks(await reopened.load());
      expect(loaded.last.priority, 1);
      expect(loaded.first.done, true);
      await reopened.close();
      final malformed = jsonDecode(await file.readAsString());
      malformed['tasks'][0].remove('position');
      await file.writeAsString(jsonEncode(malformed));
      await expectLater(reopened.load(), throwsFormatException);
      await expectLater(reopened.save([]), throwsStateError);
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );

  test(
    'pending placement survives restart and merges with remote edits and stamps',
    () async {
      final dir = await Directory.systemTemp.createTemp('memo_priority_sync_');
      final file = File('${dir.path}/account.json');
      final store = SyncTaskStore(file, 'owner');
      await store.load();
      const original = Task(id: 'a', title: 'Original');
      await store.merge([original], {});
      await store.save([original.placed(2, 3)]);
      expect(store.pending.single.kind, 'placement');
      final id = store.pending.single.id;
      await store.close();
      final reopened = SyncTaskStore(file, 'owner');
      await reopened.load();
      final remote = original.copyWith(
        title: 'Remote edit',
        done: true,
        attempts: [Attempt(id: 'remote', at: DateTime.utc(2026))],
      );
      final merged = await reopened.merge([remote], {});
      expect(merged.single.priority, 2);
      expect(merged.single.position, 3);
      expect(merged.single.title, 'Remote edit');
      expect(merged.single.done, true);
      expect(merged.single.attempts, hasLength(1));
      await reopened.merge(merged, {id});
      expect(reopened.pending, isEmpty);
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );

  testWidgets(
    'drag reorders within groups and changes priority across groups',
    (tester) async {
      final c = TaskController(
        MemoryStore([
          const Task(id: 'a', title: 'Alpha'),
          const Task(id: 'b', title: 'Beta', position: 1),
          const Task(id: 'c', title: 'Gamma', priority: 1),
        ]),
      );
      await c.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PriorityTaskList(controller: c)),
        ),
      );
      // Production page rebuilds on controller notifications.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => PriorityTaskList(controller: c),
            ),
          ),
        ),
      );
      Finder handle(String id) => find.descendant(
        of: find.byKey(ValueKey(id)),
        matching: find.byIcon(Icons.drag_indicator),
      );
      Future<void> drag(String id, Finder destination) async {
        final g = await tester.startGesture(
          tester.getCenter(handle(id)),
          kind: PointerDeviceKind.mouse,
        );
        await g.moveBy(const Offset(0, 12));
        await tester.pump();
        await g.moveTo(tester.getCenter(destination));
        await tester.pump();
        await g.up();
        await tester.pumpAndSettle();
      }

      await drag('b', find.text('Alpha'));
      expect(c.tasks.map((t) => t.id), ['b', 'a', 'c']);
      await drag('b', find.byKey(const ValueKey('group-1')));
      expect(c.tasks.first.id, 'a');
      expect(c.tasks.where((t) => t.priority == 1).map((t) => t.id), [
        'b',
        'c',
      ]);
      await drag('a', find.byKey(const ValueKey('end-1')));
      expect(c.tasks.map((t) => t.id), ['b', 'c', 'a']);
      expect(find.text('No unclassified tasks'), findsOneWidget);
      await drag('c', find.byKey(const ValueKey('group-null')));
      expect(c.tasks.first.id, 'c');
      expect(c.tasks.first.priority, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'priority dialog creates a numbered group and keeps failed drafts',
    (tester) async {
      final store = MemoryStore([const Task(id: 'a', title: 'Alpha')]);
      final c = TaskController(store);
      await c.load();
      await tester.pumpWidget(MemoApp(controller: c));
      await tester.tap(find.byTooltip('Task options for Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set priority'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Unclassified'));
      await tester.pumpAndSettle();
      final number = find.widgetWithText(TextField, 'Priority number');
      await tester.enterText(number, '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a whole number'), findsOneWidget);
      await tester.enterText(number, '12');
      store.fail = true;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save the priority. Please try again.'),
        findsOneWidget,
      );
      expect(c.tasks.single.priority, isNull);
      store.fail = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Priority 12'), findsOneWidget);
      expect(c.tasks.single.priority, 12);
    },
  );
  testWidgets(
    'touch drag auto-scrolls a long list and can reach its last slot',
    (tester) async {
      final c = TaskController(
        MemoryStore([
          for (var i = 0; i < 20; i++)
            Task(id: '$i', title: 'Task $i', position: i),
        ]),
      );
      await c.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => PriorityTaskList(controller: c),
            ),
          ),
        ),
      );
      final handle = find.descendant(
        of: find.byKey(const ValueKey('0')),
        matching: find.byIcon(Icons.drag_indicator),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();
      final listRect = tester.getRect(find.byType(ListView));
      await gesture.moveTo(Offset(listRect.center.dx, listRect.bottom - 8));
      for (var frame = 0; frame < 300; frame++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('end-null'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.tasks.last.id, '0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('priority controls fit a small phone with the keyboard visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = TaskController(
      MemoryStore([
        const Task(
          id: 'a',
          title: 'A long task description that wraps',
          priority: 1,
        ),
      ]),
    );
    await c.load();
    await tester.pumpWidget(MemoApp(controller: c));
    await tester.tap(
      find.byTooltip('Task options for A long task description that wraps'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set priority'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.tasks.single.priority, 1);
  });
  test(
    'v3 account upgrade retains pending changes and history with a backup',
    () async {
      final dir = await Directory.systemTemp.createTemp('memo_priority_v3_');
      final file = File('${dir.path}/account.json');
      final stamp = Attempt(id: 'stamp', at: DateTime.utc(2026));
      final oldTask =
          Task(id: 'a', title: 'Offline edit', attempts: [stamp]).toJson()
            ..remove('priority')
            ..remove('position');
      final original = jsonEncode({
        'version': 3,
        'tasks': [oldTask],
        'sync': {
          'owner': 'owner',
          'imported': true,
          'pending': [
            {
              'id': 'old-op',
              'kind': 'title',
              'task_id': 'a',
              'value': 'Offline edit',
            },
          ],
        },
      });
      await file.writeAsString(original);
      final store = SyncTaskStore(file, 'owner');
      final c = TaskController(store);
      await c.load();
      expect(store.pending.single.id, 'old-op');
      await c.setPriority('a', 7);
      expect(store.pending.map((o) => o.kind), ['title', 'placement']);
      expect(store.imported, true);
      expect(c.tasks.single.attempts.single.id, 'stamp');
      expect(await File('${file.path}.v3.bak').readAsString(), original);
      await store.close();
      final next = SyncTaskStore(file, 'owner');
      expect((await next.load()).single.priority, 7);
      expect(next.pending.first.id, 'old-op');
      await next.close();
      await dir.delete(recursive: true);
    },
  );
}
