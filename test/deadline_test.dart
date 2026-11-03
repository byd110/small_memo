import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:small_memo/deadline.dart';
import 'package:small_memo/deadline_views.dart';
import 'package:small_memo/main.dart';
import 'package:small_memo/sync_store.dart';
import 'package:small_memo/task.dart';
import 'package:small_memo/task_controller.dart';
import 'package:small_memo/task_store.dart';

import 'widget_test.dart' show MemoryStore;

void main() {
  test(
    'Eastern default follows DST; fixed EST does not; gaps and folds are explicit',
    () {
      expect(Deadline.defaultZone, 'America/Toronto');
      final winter = Deadline.candidates(
        Deadline.defaultZone,
        DateTime(2026, 1, 15),
        17,
        0,
      ).single;
      final summer = Deadline.candidates(
        Deadline.defaultZone,
        DateTime(2026, 7, 15),
        17,
        0,
      ).single;
      expect(winter, DateTime.utc(2026, 1, 15, 22));
      expect(summer, DateTime.utc(2026, 7, 15, 21));
      expect(Deadline(summer, Deadline.defaultZone).abbreviation, 'EDT');
      expect(Deadline(winter, Deadline.defaultZone).abbreviation, 'EST');
      expect(
        Deadline.candidates('Etc/GMT+5', DateTime(2026, 7, 15), 17, 0).single,
        DateTime.utc(2026, 7, 15, 22),
      );
      expect(
        Deadline.candidates(Deadline.defaultZone, DateTime(2026, 3, 8), 2, 30),
        isEmpty,
      );
      expect(
        Deadline.candidates(Deadline.defaultZone, DateTime(2026, 11, 1), 1, 30),
        [DateTime.utc(2026, 11, 1, 5, 30), DateTime.utc(2026, 11, 1, 6, 30)],
      );
    },
  );

  test(
    'status uses deadline zone and the exact instant; finished tasks are neutral',
    () {
      final deadline = Deadline(
        DateTime.utc(2026, 7, 16, 1),
        Deadline.defaultZone,
      ); // July 15, 21:00 Eastern.
      expect(
        deadlineStatus(deadline, false, DateTime.utc(2026, 7, 16, 0)),
        'Due today',
      );
      expect(
        deadlineStatus(deadline, false, DateTime.utc(2026, 7, 15, 1)),
        'Due tomorrow',
      );
      expect(
        deadlineStatus(
          deadline,
          false,
          deadline.at.subtract(const Duration(seconds: 1)),
        ),
        'Due today',
      );
      expect(deadlineStatus(deadline, false, deadline.at), 'Overdue');
      expect(deadlineStatus(deadline, true, DateTime.utc(2027)), 'Deadline');
    },
  );

  test(
    'deadline is optional and survives edits, attempts, ordering, completion and archive',
    () async {
      final store = MemoryStore();
      final c = TaskController(store);
      await c.load();
      final due = Deadline(DateTime.utc(2027, 1, 1), Deadline.defaultZone);
      await c.add('Task', priority: 1, deadline: due);
      final id = c.tasks.single.id;
      await c.edit(id, 'Edited');
      await c.recordAttempt(id);
      await c.setPriority(id, 2);
      await c.toggle(id);
      await c.archive(id);
      expect(c.tasks.single.deadline, due);
      expect(c.tasks.single.attempts, hasLength(1));
      expect(c.tasks.single.archived, true);
      store.fail = true;
      expect(await c.setDeadline(id, null), false);
      expect(c.tasks.single.deadline, due);
      store.fail = false;
      await c.setDeadline(id, null);
      expect(c.tasks.single.deadline, isNull);
      expect(c.tasks.single.archived, true);
    },
  );

  test(
    'v5 upgrade backs up and preserves data; malformed v6 deadlines are rejected',
    () async {
      final dir = await Directory.systemTemp.createTemp('memo_deadline_');
      final file = File('${dir.path}/tasks.json');
      final old = const Task(id: 'a', title: 'Existing').toJson()
        ..remove('deadline');
      final original = jsonEncode({
        'version': 5,
        'tasks': [old],
      });
      await file.writeAsString(original);
      final store = FileTaskStore(file);
      final tasks = await store.load();
      expect(tasks.single.deadline, isNull);
      final due = Deadline(DateTime.utc(2026, 12, 1, 17), Deadline.defaultZone);
      await store.save([tasks.single.withDeadline(due)]);
      await store.close();
      expect(await File('${file.path}.v5.bak').readAsString(), original);
      final reopened = FileTaskStore(file);
      expect((await reopened.load()).single.deadline, due);
      await reopened.close();
      final bad = jsonDecode(await file.readAsString());
      bad['tasks'][0]['deadline']['zone'] = 'Unknown';
      await file.writeAsString(jsonEncode(bad));
      await expectLater(reopened.load(), throwsFormatException);
      await expectLater(reopened.save([]), throwsStateError);
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );

  test(
    'offline deadline set/remove survives restart and merges independent remote edits',
    () async {
      final dir = await Directory.systemTemp.createTemp('memo_deadline_sync_');
      final file = File('${dir.path}/account.json');
      final store = SyncTaskStore(file, 'owner');
      await store.load();
      const task = Task(id: 'a', title: 'Original');
      await store.merge([task], {});
      final due = Deadline(DateTime.utc(2026, 12, 1), Deadline.defaultZone);
      await store.save([task.withDeadline(due)]);
      expect(store.pending.single.kind, 'deadline');
      final id = store.pending.single.id;
      await store.close();
      final reopened = SyncTaskStore(file, 'owner');
      await reopened.load();
      final remote = task.copyWith(
        title: 'Remote',
        attempts: [Attempt(id: 'attempt', at: DateTime.utc(2026))],
      );
      final merged = await reopened.merge([remote], {});
      expect(merged.single.deadline, due);
      expect(merged.single.title, 'Remote');
      expect(merged.single.attempts, hasLength(1));
      await reopened.merge(merged, {id});
      await reopened.save([merged.single.withDeadline(null)]);
      expect(reopened.pending.single.value, isNull);
      expect((await reopened.merge(merged, {})).single.deadline, isNull);
      expect(
        replay([], reopened.pending),
        isEmpty,
      ); // A deleted task is not resurrected.
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );

  testWidgets(
    'create with deadline, change and remove without losing history',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = TaskController(MemoryStore());
      await c.load();
      await tester.pumpWidget(MemoApp(controller: c));
      await tester.enterText(
        find.widgetWithText(TextField, 'New task'),
        'Read',
      );
      await tester.tap(find.text('Add deadline (optional)'));
      await tester.pumpAndSettle();
      expect(find.text('Eastern · Toronto / New York'), findsOneWidget);
      expect(find.text('17:00'), findsOneWidget);
      await tester.tap(find.text('Tomorrow'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add task'));
      await tester.pumpAndSettle();
      expect(c.tasks.single.deadline, isNotNull);
      expect(
        find.text('Add deadline (optional)'),
        findsOneWidget,
      ); // New task has no inherited deadline.
      await c.recordAttempt(c.tasks.single.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Task options for Read'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change deadline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Task options for Read'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove deadline'));
      await tester.pumpAndSettle();
      expect(c.tasks.single.deadline, isNull);
      expect(c.tasks.single.attempts, hasLength(1));
    },
  );

  testWidgets(
    'DST gap cannot save; repeated time requires an explicit occurrence',
    (tester) async {
      Deadline? saved;
      Future<void> open(Deadline initial) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => DeadlineDialog(
                      initial: initial,
                      onSave: (value) async {
                        saved = value;
                        return true;
                      },
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged!('America/Toronto');
        await tester.pumpAndSettle();
      }

      await open(Deadline(DateTime.utc(2026, 3, 8, 7, 30), 'Etc/GMT+5'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.textContaining('skipped by daylight saving'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await open(Deadline(DateTime.utc(2026, 11, 1, 6, 30), 'Etc/GMT+5'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.textContaining('Choose which occurrence'), findsOneWidget);
      await tester.tap(find.text('EDT · 05:30 UTC'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!.at, DateTime.utc(2026, 11, 1, 5, 30));
    },
  );

  testWidgets('deadline dialog fits small phone and retains failed draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Deadline? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => DeadlineDialog(
                  onSave: (value) async {
                    saved = value;
                    return false;
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(find.textContaining('Could not save the deadline'), findsOneWidget);
    expect(find.byType(DeadlineDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
