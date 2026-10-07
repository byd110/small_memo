import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:small_memo/task.dart';
import 'package:small_memo/task_store.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('small_memo_test_');
    file = File('${directory.path}/tasks.json');
  });
  tearDown(() async => directory.delete(recursive: true));

  test('tasks and completion survive close and reopen', () async {
    final first = FileTaskStore(file);
    expect(await first.load(), isEmpty);
    await first.save([const Task(id: 'a', title: 'Read 中文 🍵')]);
    await first.save([const Task(id: 'a', title: 'Read 中文 🍵', done: true)]);
    await first.close();
    final second = FileTaskStore(file);
    final tasks = await second.load();
    expect(tasks.single.title, 'Read 中文 🍵');
    expect(tasks.single.done, isTrue);
    await second.save([]);
    await second.close();
    final third = FileTaskStore(file);
    expect(await third.load(), isEmpty);
    await third.close();
  });

  test('malformed data is preserved and cannot be overwritten', () async {
    const invalid = '{broken';
    await file.writeAsString(invalid);
    final store = FileTaskStore(file);
    await expectLater(store.load(), throwsFormatException);
    await expectLater(store.save([]), throwsStateError);
    expect(await file.readAsString(), invalid);
    await store.close();
  });

  test('unknown schema and duplicate IDs are rejected', () async {
    final store = FileTaskStore(file);
    await file.writeAsString('{"version":2,"tasks":[]}');
    await expectLater(store.load(), throwsFormatException);
    await file.writeAsString(
      '{"version":1,"tasks":['
      '{"id":"a","title":"One","done":false},'
      '{"id":"a","title":"Two","done":false}]}',
    );
    await expectLater(store.load(), throwsFormatException);
    await store.close();
  });

  test('interrupted temporary write does not replace saved data', () async {
    final store = FileTaskStore(file);
    await store.load();
    await store.save([const Task(id: 'a', title: 'Keep me')]);
    await store.close();
    await File('${file.path}.tmp').writeAsString('{partial');
    final reopened = FileTaskStore(file);
    expect((await reopened.load()).single.title, 'Keep me');
    await reopened.close();
  });
}
