import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'task_controller.dart';
import 'task_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  String? shortcutNotice;
  if (desktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Small Memo',
        size: Size(420, 600),
        minimumSize: Size(340, 400),
        center: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    try {
      if (Platform.isLinux &&
          Platform.environment['XDG_SESSION_TYPE'] == 'wayland') {
        throw UnsupportedError('Global shortcut requires X11');
      }
      await hotKeyManager.register(
        HotKey(
          key: PhysicalKeyboardKey.keyM,
          modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
        ),
        keyDownHandler: (_) async {
          await windowManager.restore();
          await windowManager.show();
          await windowManager.focus();
        },
      );
    } catch (_) {
      shortcutNotice =
          'Shortcut unavailable. Open Small Memo from the taskbar.';
    }
  }
  try {
    final directory = await getApplicationSupportDirectory();
    final store = FileTaskStore(File('${directory.path}/tasks.json'));
    final controller = TaskController(store);
    runApp(
      MemoApp(
        controller: controller,
        desktop: desktop,
        shortcutNotice: shortcutNotice,
      ),
    );
    await controller.load();
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'Small Memo could not open its storage.\n$e',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MemoApp extends StatelessWidget {
  const MemoApp({
    super.key,
    required this.controller,
    this.desktop = false,
    this.shortcutNotice,
  });
  final TaskController controller;
  final bool desktop;
  final String? shortcutNotice;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Small Memo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF426B50)),
      scaffoldBackgroundColor: const Color(0xFFFAF9F6),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    ),
    home: MemoPage(
      controller: controller,
      desktop: desktop,
      shortcutNotice: shortcutNotice,
    ),
  );
}

class MemoPage extends StatefulWidget {
  const MemoPage({
    super.key,
    required this.controller,
    required this.desktop,
    this.shortcutNotice,
  });
  final TaskController controller;
  final bool desktop;
  final String? shortcutNotice;

  @override
  State<MemoPage> createState() => _MemoPageState();
}

class _MemoPageState extends State<MemoPage> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (await widget.controller.add(_text.text) && mounted) {
      _text.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      if (widget.desktop)
        const SingleActivator(LogicalKeyboardKey.escape): () {
          windowManager.minimize();
        },
      const SingleActivator(LogicalKeyboardKey.keyN, control: true):
          _focus.requestFocus,
    },
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final controller = widget.controller;
                  final remaining = controller.tasks
                      .where((task) => !task.done)
                      .length;
                  final tasks = [
                    ...controller.tasks.where((task) => !task.done),
                    ...controller.tasks.where((task) => task.done),
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Small Memo',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$remaining ${remaining == 1 ? 'thing' : 'things'} to do',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _text,
                              focusNode: _focus,
                              autofocus: widget.desktop,
                              enabled: controller.ready && !controller.busy,
                              maxLength: 500,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                hintText: 'What needs doing?',
                                labelText: 'New task',
                                counterText: '',
                              ),
                              onSubmitted: (_) => _add(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 56,
                            child: IconButton.filled(
                              tooltip: 'Add task',
                              onPressed: controller.ready && !controller.busy
                                  ? _add
                                  : null,
                              icon: const Icon(Icons.add),
                            ),
                          ),
                        ],
                      ),
                      if (controller.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              controller.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      if (!controller.ready && !controller.busy)
                        TextButton(
                          onPressed: controller.load,
                          child: const Text('Try again'),
                        ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: !controller.ready
                            ? Center(
                                child: controller.busy
                                    ? const CircularProgressIndicator()
                                    : const Icon(Icons.folder_off_outlined),
                              )
                            : tasks.isEmpty
                            ? Center(
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 44,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(height: 12),
                                      const Text('A little room to think.'),
                                      const SizedBox(height: 4),
                                      const Text('Add your first task above.'),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: tasks.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final task = tasks[index];
                                  return Padding(
                                    key: ValueKey(task.id),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: task.done,
                                          semanticLabel: task.title,
                                          onChanged: controller.busy
                                              ? null
                                              : (_) =>
                                                    controller.toggle(task.id),
                                        ),
                                        Expanded(
                                          child: Text(
                                            task.title,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: task.done
                                                  ? Colors.grey.shade600
                                                  : null,
                                              decoration: task.done
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete ${task.title}',
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                          onPressed: controller.busy
                                              ? null
                                              : () async {
                                                  final confirmed =
                                                      await showDialog<bool>(
                                                        context: context,
                                                        builder: (context) => AlertDialog(
                                                          title: const Text(
                                                            'Delete task?',
                                                          ),
                                                          content: Text(
                                                            task.title,
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    false,
                                                                  ),
                                                              child: const Text(
                                                                'Cancel',
                                                              ),
                                                            ),
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    true,
                                                                  ),
                                                              child: const Text(
                                                                'Delete',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                  if (confirmed == true) {
                                                    await controller.delete(
                                                      task.id,
                                                    );
                                                  }
                                                },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.desktop
                            ? widget.shortcutNotice ??
                                  'Ctrl+Alt+M to open · Esc to minimize'
                            : 'Saved on this device',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (widget.desktop)
                        Text(
                          'Saved on this device',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
