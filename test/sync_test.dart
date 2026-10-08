import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:small_memo/sync_service.dart';
import 'package:small_memo/sync_store.dart';
import 'package:small_memo/task.dart';
import 'package:small_memo/task_controller.dart';
import 'package:small_memo/task_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const owner = '11111111-1111-4111-8111-111111111111';
const otherOwner = '22222222-2222-4222-8222-222222222222';

class DelayedRemote implements MemoRemote {
  final calls = <List<MemoOperation>>[];
  final owners = <String>[];
  final replies = <Completer<List<Task>>>[];
  @override
  Future<List<Task>> exchange(String owner, List<MemoOperation> ops) {
    owners.add(owner);
    calls.add(ops);
    final reply = Completer<List<Task>>();
    replies.add(reply);
    return reply.future;
  }
}

Future<void> setUser(SupabaseClient client, String id) async {
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': 'test-token',
      'refresh_token': 'test-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'user': {
        'id': id,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-07T00:00:00Z',
        'email': '$id@example.com',
      },
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final stores = <FileTaskStore>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('memo_sync_');
  });
  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    await directory.delete(recursive: true);
  });
  SyncTaskStore makeStore([String name = 'account']) {
    final store = SyncTaskStore(File('${directory.path}/$name.json'), owner);
    stores.add(store);
    return store;
  }

  test(
    'offline edits and operation IDs survive restart; failed writes preserve queue',
    () async {
      final store = makeStore();
      final controller = TaskController(store);
      await controller.load();
      await controller.add('Read');
      await controller.recordAttempt(controller.tasks.single.id);
      await controller.edit(controller.tasks.single.id, 'Read again');
      final ids = store.pending.map((o) => o.id).toList();
      await store.close();
      final reopened = makeStore();
      final tasks = await reopened.load();
      expect(tasks.single.title, 'Read again');
      expect(tasks.single.attempts, hasLength(1));
      expect(reopened.pending.map((o) => o.id), ids);
      // An existing directory where the temp file should be causes a real disk error.
      await Directory('${reopened.file.path}.tmp').create();
      await expectLater(reopened.save([]), throwsA(isA<FileSystemException>()));
      expect(reopened.pending.map((o) => o.id), ids);
      final disk = jsonDecode(await reopened.file.readAsString());
      expect(disk['tasks'], hasLength(1));
    },
  );

  test(
    'merging response retains edits and attempts made during the request',
    () async {
      final store = makeStore();
      final controller = TaskController(store);
      await controller.load();
      await controller.add('First title');
      final initial = controller.tasks.single;
      final sent = store.pending.map((o) => o.id).toSet();
      await controller.edit(initial.id, 'New title');
      await controller.recordAttempt(initial.id);
      final remoteAttempt = Attempt(
        id: 'remote',
        at: DateTime.utc(2026, 10, 7),
      );
      final merged = await store.merge([
        initial.copyWith(done: true, attempts: [remoteAttempt]),
      ], sent);
      expect(merged.single.title, 'New title');
      expect(merged.single.done, true);
      expect(merged.single.attempts, hasLength(2));
      expect(store.pending.map((o) => o.kind), ['title', 'attempt']);
    },
  );

  test(
    'deleted remote task is not resurrected by pending edits or attempts',
    () async {
      final store = makeStore();
      await store.load();
      const task = Task(id: 't', title: 'Keep');
      await store.merge([task], {});
      await store.save([
        task.copyWith(
          title: 'Changed',
          attempts: [Attempt(id: 'a', at: DateTime.utc(2026))],
        ),
      ]);
      expect(await store.merge([], {}), isEmpty);
      expect(
        store.pending,
        hasLength(2),
      ); // Retry safely; server deletion wins.
    },
  );

  test(
    'local import is explicit, keeps original history, and is durable once-only',
    () async {
      final guest = FileTaskStore(File('${directory.path}/tasks.json'));
      stores.add(guest);
      await guest.load();
      final task = Task(
        id: 't',
        title: 'Local',
        done: true,
        attempts: [Attempt(id: 'a', at: DateTime.utc(2026))],
      );
      await guest.save([task]);
      final original = await guest.file.readAsString();
      final store = makeStore();
      expect(await store.load(), isEmpty);
      expect(await store.importLocal([task]), hasLength(1));
      expect(store.pending.map((o) => o.kind), ['create', 'attempt']);
      await store.close();
      final reopened = makeStore();
      await reopened.load();
      await reopened.importLocal([
        const Task(id: 'another', title: 'No duplicate import'),
      ]);
      expect(reopened.pending, hasLength(2));
      expect(await guest.file.readAsString(), original);
    },
  );

  test(
    'wrong account and malformed queue cannot overwrite saved data',
    () async {
      final store = makeStore();
      await store.load();
      await store.save([const Task(id: 't', title: 'Private')]);
      await store.close();
      final original = await store.file.readAsString();
      final wrong = SyncTaskStore(store.file, otherOwner);
      stores.add(wrong);
      await expectLater(wrong.load(), throwsFormatException);
      await expectLater(wrong.save([]), throwsStateError);
      expect(await store.file.readAsString(), original);
      final data = jsonDecode(original);
      data['sync']['pending'][0]['kind'] = 'unknown';
      await store.file.writeAsString(jsonEncode(data));
      await expectLater(store.load(), throwsFormatException);
      await expectLater(store.save([]), throwsStateError);
    },
  );

  test(
    'service retries same IDs after lost response; edits during sync survive',
    () async {
      final store = makeStore();
      final controller = TaskController(store);
      await controller.load();
      await controller.add('Original');
      final client = SupabaseClient(
        'https://example.com',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await setUser(client, owner);
      final remote = DelayedRemote();
      final service = SyncService(
        controller,
        directory,
        client,
        remote: remote,
      );
      addTearDown(() async {
        service.dispose();
        await client.dispose();
      });
      final first = service.sync();
      final original = controller.tasks.single;
      remote.replies[0].completeError(const SocketException('Response lost'));
      await first;
      expect(service.error, isNotNull);
      expect(store.pending, hasLength(1));
      final second = service.sync();
      expect(remote.calls[1].single.id, remote.calls[0].single.id);
      await controller.edit(original.id, 'While waiting');
      remote.replies[1].complete([original]);
      // First response commits then the service sends the remaining title edit.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.tasks.single.title, 'While waiting');
      expect(remote.calls[2].single.kind, 'title');
      remote.replies[2].complete([original.copyWith(title: 'While waiting')]);
      await second;
      expect(store.pending, isEmpty);
      expect(service.error, isNull);
    },
  );

  test(
    'account change during request cannot replace or upload the other account cache',
    () async {
      final store = makeStore();
      final controller = TaskController(store);
      await controller.load();
      await controller.add('Account A');
      final client = SupabaseClient(
        'https://example.com',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await setUser(client, owner);
      final remote = DelayedRemote();
      final service = SyncService(
        controller,
        directory,
        client,
        remote: remote,
      );
      addTearDown(() async {
        service.dispose();
        await client.dispose();
      });
      final running = service.sync();
      final original = controller.tasks.single;
      final another = SyncTaskStore(
        File('${directory.path}/other.json'),
        otherOwner,
      );
      stores.add(another);
      await controller.changeStore(another);
      await setUser(client, otherOwner);
      await controller.add('Account B');
      remote.replies.single.complete([original]);
      await running;
      expect(controller.tasks.single.title, 'Account B');
      expect(another.pending, hasLength(1));
      expect(remote.owners, [owner]);
      // Reopen A: its pending change is retained, ready for an idempotent retry.
      final reopened = makeStore();
      expect((await reopened.load()).single.title, 'Account A');
      expect(reopened.pending, hasLength(1));
    },
  );
  test(
    'import merges missing history without overwriting account edits',
    () async {
      final store = makeStore();
      await store.load();
      final remoteAttempt = Attempt(id: 'remote', at: DateTime.utc(2026));
      final localAttempt = Attempt(id: 'local', at: DateTime.utc(2026, 2));
      final remote = Task(
        id: 't',
        title: 'Edited online',
        done: true,
        attempts: [remoteAttempt],
      );
      await store.merge([remote], {});
      final tasks = await store.importLocal([
        Task(
          id: 't',
          title: 'Old local title',
          attempts: [remoteAttempt, localAttempt],
        ),
      ]);
      expect(tasks.single.title, 'Edited online');
      expect(tasks.single.done, true);
      expect(tasks.single.attempts, hasLength(2));
      expect(store.pending.single.kind, 'attempt');
    },
  );
}
