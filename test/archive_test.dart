import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:small_memo/main.dart';
import 'package:small_memo/sync_store.dart';
import 'package:small_memo/task.dart';
import 'package:small_memo/task_controller.dart';

import 'widget_test.dart' show MemoryStore;

void main() {
  test(
    'completion dates, exact 30-day boundary, reopening and history',
    () async {
      var now = DateTime.utc(2026, 1, 1);
      final c = TaskController(MemoryStore(), now: () => now);
      await c.load();
      expect(await c.add('Important', priority: 1), true);
      final id = c.tasks.single.id;
      await c.recordAttempt(id);
      await c.toggle(id);
      expect(c.tasks.single.completedAt, now);
      now = now
          .add(const Duration(days: 30))
          .subtract(const Duration(seconds: 1));
      await c.archiveExpired();
      expect(c.tasks.single.archived, false);
      now = now.add(const Duration(seconds: 1));
      await c.archiveExpired();
      expect(c.tasks.single.archivedAt, now);
      await c.edit(id, 'Edited archived task');
      expect(c.tasks.single.attempts, hasLength(1));
      expect(c.tasks.single.priority, 1);
      await c.toggle(id);
      expect(c.tasks.single.done, false);
      expect(c.tasks.single.completedAt, isNull);
      expect(c.tasks.single.archivedAt, isNull);
      await c.toggle(id);
      expect(c.tasks.single.completedAt, now);
    },
  );

  test('legacy grace period and failed archive save are safe', () async {
    final now = DateTime.utc(2026, 10, 24);
    final store = MemoryStore()
      ..tasks = [const Task(id: 'old', title: 'Old', done: true)];
    final c = TaskController(store, now: () => now);
    await c.load();
    expect(c.tasks.single.completedAt, now);
    expect(c.tasks.single.archived, false);
    store.fail = true;
    expect(await c.archive('old'), false);
    expect(c.tasks.single.archived, false);
    store.fail = false;
    await c.add('Open');
    await c.archiveAllFinished();
    expect(c.tasks.where((t) => t.archived).single.id, 'old');
    expect(c.tasks.where((t) => !t.done).single.archived, false);
  });

  test(
    'archive outbox survives restart and merges remote description and attempts',
    () async {
      final dir = await Directory.systemTemp.createTemp('memo_archive_');
      final file = File('${dir.path}/account.json');
      final store = SyncTaskStore(file, 'owner');
      await store.load();
      final task = Task(
        id: 'a',
        title: 'Original',
        done: true,
        completedAt: DateTime.utc(2026, 1, 1),
      );
      await store.merge([task], {});
      final archived = task.lifecycle(
        true,
        task.completedAt,
        DateTime.utc(2026, 2, 1),
      );
      await store.save([archived]);
      final operationId = store.pending.single.id;
      await store.close();
      final reopened = SyncTaskStore(file, 'owner');
      await reopened.load();
      final merged = await reopened.merge([
        task.copyWith(
          title: 'Other device',
          attempts: [Attempt(id: 'stamp', at: DateTime.utc(2026, 1, 5))],
        ),
      ], {});
      expect(merged.single.archived, true);
      expect(merged.single.title, 'Other device');
      expect(merged.single.attempts, hasLength(1));
      await reopened.merge(merged, {operationId});
      expect(reopened.pending, isEmpty);
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );

  test(
    'a delayed archive does not override a reopen or a later completion',
    () {
      final completed = Task(
        id: 'a',
        title: 'A',
        done: true,
        completedAt: DateTime.utc(2026, 1, 1),
      );
      final archived = completed.lifecycle(
        true,
        completed.completedAt,
        DateTime.utc(2026, 2, 1),
      );
      final changes = changesBetween([completed], [archived]);
      expect(changes.single.kind, 'archive');
      final reopened = completed.lifecycle(false, null, null);
      expect(replay([reopened], changes).single.done, false);
      final completedAgain = completed.lifecycle(
        true,
        DateTime.utc(2026, 2, 2),
        null,
      );
      expect(replay([completedAgain], changes).single.archived, false);
    },
  );

  testWidgets('priority entry, Finished at end, manual archive and reopen', (
    tester,
  ) async {
    final c = TaskController(MemoryStore());
    await c.load();
    await tester.pumpWidget(MemoApp(controller: c));
    await tester.enterText(find.widgetWithText(TextField, 'New task'), 'First');
    await tester.enterText(find.widgetWithText(TextField, 'Priority'), '1');
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(c.tasks.single.priority, 1);
    final id = c.tasks.single.id;
    await c.add('Unclassified task');
    await c.toggle(id);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Finished')).dy,
      greaterThan(tester.getTopLeft(find.text('Unclassified task')).dy),
    );
    await tester.tap(find.text('Archive all'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('No archived tasks.'), findsOneWidget);
    expect(c.tasks.firstWhere((t) => t.id == id).done, false);
    expect(c.tasks.firstWhere((t) => t.id == id).priority, 1);
  });
}
