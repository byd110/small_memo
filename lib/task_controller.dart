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

  List<Task> get tasks => List.unmodifiable(orderedTasks(_tasks));

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
      await archiveExpired();
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
      await archiveExpired();
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
      await archiveExpired();
    }
  }

  Future<bool> add(String title, {int? priority}) async {
    title = title.trim();
    if (title.isEmpty || title.length > 500) return false;
    if (!Task.validPriority(priority)) return false;
    final group = tasks.where((t) => t.priority == priority);
    final position = group.isEmpty ? 0 : group.last.position + 1;
    return _save([
      ..._tasks,
      Task(
        id: const Uuid().v4(),
        title: title,
        priority: priority,
        position: position,
      ),
    ]);
  }

  /// Move before a destination task, or append when beforeId is absent.
  Future<bool> move(String id, int? priority, {String? beforeId}) async {
    if (!ready || busy || !Task.validPriority(priority)) return false;
    final task = _tasks.where((t) => t.id == id).firstOrNull;
    if (task == null || beforeId == id) return false;
    final group = tasks
        .where(
          (t) =>
              t.priority == priority &&
              t.id != id &&
              t.done == task.done &&
              t.archived == task.archived,
        )
        .toList();
    final index = beforeId == null
        ? group.length
        : group.indexWhere((t) => t.id == beforeId);
    if (index < 0) return false; // Destination changed while dragging.
    group.insert(index, task.placed(priority, 0));
    final replacements = {
      for (var i = 0; i < group.length; i++)
        group[i].id: group[i].placed(priority, i),
    };
    return _save([for (final t in _tasks) replacements[t.id] ?? t]);
  }

  Future<bool> setPriority(String id, int? priority) async {
    if (!ready || busy) return false;
    final task = _tasks.where((t) => t.id == id).firstOrNull;
    if (task == null || !Task.validPriority(priority)) return false;
    if (task.priority == priority) return true;
    return move(id, priority);
  }

  Future<bool> toggle(String id) => _save([
    for (final task in _tasks)
      if (task.id == id)
        task.lifecycle(!task.done, task.done ? null : _now().toUtc(), null)
      else
        task,
  ]);

  /// Old completed tasks have no known completion date: start their grace period now.
  Future<bool> archiveExpired() async {
    if (!ready || busy) return false;
    final now = _now().toUtc();
    var changed = false;
    final next = tasks.map((task) {
      if (!task.done || task.archived) return task;
      if (task.completedAt == null) {
        changed = true;
        return task.lifecycle(true, now, null);
      }
      if (!task.completedAt!.add(const Duration(days: 30)).isAfter(now)) {
        changed = true;
        return task.lifecycle(true, task.completedAt, now);
      }
      return task;
    }).toList();
    return !changed || await _save(next);
  }

  Future<bool> archive(String id) async {
    final task = tasks.where((t) => t.id == id).firstOrNull;
    if (task == null || !task.done || task.archived) return false;
    final now = _now().toUtc();
    return _update(id, (t) => t.lifecycle(true, t.completedAt ?? now, now));
  }

  Future<bool> archiveAllFinished() {
    final now = _now().toUtc();
    return _save([
      for (final t in _tasks)
        if (t.done && !t.archived)
          t.lifecycle(true, t.completedAt ?? now, now)
        else
          t,
    ]);
  }

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
