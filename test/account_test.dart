import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:small_memo/main.dart';
import 'package:small_memo/sync_service.dart';
import 'package:small_memo/task_controller.dart';
import 'package:small_memo/task.dart';
import 'package:small_memo/task_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocalMemoryStore implements TaskStore {
  List<Task> tasks = [];
  @override
  Future<List<Task>> load() async => tasks;
  @override
  Future<void> save(List<Task> next) async {
    tasks = next;
  }
}

void main() {
  testWidgets('small screen account navigation keeps local use available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp;
    final store = LocalMemoryStore();
    final controller = TaskController(store);
    await controller.load();
    await controller.add('Keep local');
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://example.com',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    ))!;
    final sync = SyncService(controller, dir, client);
    addTearDown(() async {
      sync.dispose();
      await tester.runAsync(client.dispose);
    });
    await tester.pumpWidget(MemoApp(controller: controller, sync: sync));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Account & sync'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter your email address and password.'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Keep local'), findsOneWidget);
    expect(find.text('Saved on this device'), findsOneWidget);
  });
}
