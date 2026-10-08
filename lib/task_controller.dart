import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'task.dart';
import 'task_store.dart';

class TaskController extends ChangeNotifier {
  TaskController(this.store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  TaskStore store;
  List<Task> _tasks = [];
  bool ready = false;
  bool busy = false;
  String? error;

  List<Task> get tasks => List.unmodifiable(_tasks);

  /// Network requests run outside this guard; only their local commit holds it.
  Future<bool> applyExternal(Future<List<Task>> Function() change) async {
    if (!ready || busy) return false;
    busy = true;
    notifyListeners();
    try {
      _tasks = await change();
      return true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> changeStore(TaskStore next) async {
    if (busy) throw StateError('A local save is still in progress');
    ready = false;
    busy = true;
    _tasks = [];
    error = null;
    notifyListeners();
    final previous = store;
    store = next;
    try {
      if (previous is FileTaskStore) await previous.close();
      _tasks = await next.load();
      ready = true;
    } catch (_) {
      error = 'Could not open this account’s local data. Restart to retry.';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> load() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      _tasks = await store.load();
      ready = true;
    } catch (e) {
      error =
          'Could not open your tasks. Your saved file has not been changed.\n$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> add(String title) async {
    title = title.trim();
    if (title.isEmpty || title.length > 500) return false;
    return _save([..._tasks, Task(id: const Uuid().v4(), title: title)]);
  }

  Future<bool> toggle(String id) => _save([
    for (final task in _tasks)
      if (task.id == id) task.toggled() else task,
  ]);

  Future<bool> edit(String id, String title) async {
    title = title.trim();
    if (title.isEmpty || title.length > 500) return false;
    return _update(id, (task) => task.copyWith(title: title));
  }

  Future<bool> recordAttempt(String id) => _update(
    id,
    (task) => task.copyWith(
      attempts: [
        ...task.attempts,
        Attempt(id: const Uuid().v4(), at: _now().toUtc()),
      ],
    ),
  );

  Future<bool> removeAttempt(String taskId, String attemptId) => _update(
    taskId,
    (task) => task.copyWith(
      attempts: [
        for (final attempt in task.attempts)
          if (attempt.id != attemptId) attempt,
      ],
    ),
  );

  Future<bool> _update(String id, Task Function(Task) change) async {
    if (!_tasks.any((task) => task.id == id)) return false;
    return _save([
      for (final task in _tasks)
        if (task.id == id) change(task) else task,
    ]);
  }

  Future<bool> delete(String id) => _save([
    for (final task in _tasks)
      if (task.id != id) task,
  ]);

  Future<bool> _save(List<Task> next) async {
    if (!ready || busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await store.save(next);
      _tasks = next;
      return true;
    } catch (_) {
      error =
          'Could not save the change. Please check disk space and try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
