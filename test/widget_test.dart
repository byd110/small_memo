import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:small_memo/main.dart';
import 'package:small_memo/task.dart';
import 'package:small_memo/task_controller.dart';
import 'package:small_memo/task_store.dart';

class MemoryStore implements TaskStore {
  List<Task> tasks = [];
  bool fail = false;
  @override
  Future<List<Task>> load() async => tasks;
  @override
  Future<void> save(List<Task> value) async {
    if (fail) throw StateError('Disk full');
    tasks = List.of(value);
  }
}

void main() {
  testWidgets('desktop task entry gains focus after storage loads', (
    tester,
  ) async {
    final controller = TaskController(MemoryStore());
    await tester.pumpWidget(MemoApp(controller: controller, desktop: true));
    await controller.load();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('create, check, uncheck, and confirm deletion', (tester) async {
    final store = MemoryStore();
    final controller = TaskController(store);
    await controller.load();
    await tester.pumpWidget(MemoApp(controller: controller));
    expect(find.text('A little room to think.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Buy tea  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Buy tea'), findsOneWidget);
    expect(store.tasks.single.title, 'Buy tea');
    expect(find.text('1 thing to do'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(store.tasks.single.done, isTrue);
    expect(find.text('0 things to do'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(store.tasks.single.done, isFalse);
    await tester.tap(find.byTooltip('Delete Buy tea'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.tasks, hasLength(1));
    await tester.tap(find.byTooltip('Delete Buy tea'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.tasks, isEmpty);
  });

  testWidgets('failed save retains draft and displays an error', (
    tester,
  ) async {
    final store = MemoryStore()..fail = true;
    final controller = TaskController(store);
    await controller.load();
    await tester.pumpWidget(MemoApp(controller: controller));
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(controller.tasks, isEmpty);
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this draft',
    );
  });

  test(
    'blank input is ignored; failed toggle retains previous state',
    () async {
      final store = MemoryStore();
      final controller = TaskController(store);
      await controller.load();
      expect(await controller.add('   '), isFalse);
      expect(await controller.add('Read'), isTrue);
      final id = controller.tasks.single.id;
      store.fail = true;
      expect(await controller.toggle(id), isFalse);
      expect(controller.tasks.single.done, isFalse);
      store.fail = false;
      expect(await controller.toggle(id), isTrue);
      expect(controller.tasks.single.done, isTrue);
    },
  );

  testWidgets('small phone with keyboard has no layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.reset);
    final controller = TaskController(MemoryStore());
    await controller.load();
    await tester.pumpWidget(MemoApp(controller: controller));
    expect(tester.takeException(), isNull);
    (controller.store as MemoryStore).fail = true;
    await tester.enterText(find.byType(TextField), 'A task');
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });
}
