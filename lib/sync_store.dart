import 'package:uuid/uuid.dart';

import 'task.dart';
import 'task_store.dart';

/// A field-level command with a stable ID, safe to retry after a lost response.
class MemoOperation {
  const MemoOperation(this.id, this.kind, this.taskId, this.value);
  factory MemoOperation.create(String kind, String taskId, [Object? value]) =>
      MemoOperation(const Uuid().v4(), kind, taskId, value);
  final String id;
  final String kind;
  final String taskId;
  final Object? value;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'task_id': taskId,
    'value': value,
  };
  factory MemoOperation.fromJson(Map<String, dynamic> json) {
    final op = MemoOperation(
      json['id'] as String,
      json['kind'] as String,
      json['task_id'] as String,
      json['value'],
    );
    if (op.id.isEmpty ||
        op.taskId.isEmpty ||
        !{
          'create',
          'title',
          'done',
          'delete',
          'attempt',
          'remove_attempt',
        }.contains(op.kind)) {
      throw const FormatException('Invalid pending change');
    }
    // Validate payloads even when their task is no longer present.
    switch (op.kind) {
      case 'create':
        Task.fromJson(Map<String, dynamic>.from(op.value as Map));
      case 'title':
        if (op.value is! String ||
            (op.value as String).trim().isEmpty ||
            (op.value as String).length > 500) {
          throw const FormatException('Invalid title change');
        }
      case 'done':
        if (op.value is! bool) {
          throw const FormatException('Invalid completion');
        }
      case 'attempt':
        Attempt.fromJson(Map<String, dynamic>.from(op.value as Map));
      case 'remove_attempt':
        if (op.value is! String) {
          throw const FormatException('Invalid attempt ID');
        }
    }
    return op;
  }
}

List<MemoOperation> changesBetween(List<Task> before, List<Task> after) {
  final old = {for (final task in before) task.id: task};
  final nextIds = after.map((t) => t.id).toSet();
  final changes = <MemoOperation>[];
  for (final task in before) {
    if (!nextIds.contains(task.id)) {
      changes.add(MemoOperation.create('delete', task.id));
    }
  }
  for (final task in after) {
    final previous = old[task.id];
    if (previous == null) {
      // Attempts are separate operations, so simultaneous work never overwrites them.
      changes.add(
        MemoOperation.create(
          'create',
          task.id,
          task.copyWith(attempts: []).toJson(),
        ),
      );
    } else {
      if (task.title != previous.title) {
        changes.add(MemoOperation.create('title', task.id, task.title));
      }
      if (task.done != previous.done) {
        changes.add(MemoOperation.create('done', task.id, task.done));
      }
    }
    final previousIds =
        previous?.attempts.map((a) => a.id).toSet() ?? <String>{};
    final nextAttemptIds = task.attempts.map((a) => a.id).toSet();
    for (final attempt in task.attempts) {
      if (!previousIds.contains(attempt.id)) {
        changes.add(MemoOperation.create('attempt', task.id, attempt.toJson()));
      }
    }
    for (final id in previousIds.difference(nextAttemptIds)) {
      changes.add(MemoOperation.create('remove_attempt', task.id, id));
    }
  }
  return changes;
}

List<Task> replay(List<Task> tasks, Iterable<MemoOperation> operations) {
  final result = {for (final t in tasks) t.id: t};
  for (final op in operations) {
    final task = result[op.taskId];
    switch (op.kind) {
      case 'create':
        result.putIfAbsent(
          op.taskId,
          () => Task.fromJson(Map<String, dynamic>.from(op.value as Map)),
        );
      case 'delete':
        result.remove(op.taskId);
      case 'title':
        if (task != null) {
          result[op.taskId] = task.copyWith(title: op.value as String);
        }
      case 'done':
        if (task != null) {
          result[op.taskId] = task.copyWith(done: op.value as bool);
        }
      case 'attempt':
        if (task != null) {
          final attempt = Attempt.fromJson(
            Map<String, dynamic>.from(op.value as Map),
          );
          if (!task.attempts.any((a) => a.id == attempt.id)) {
            result[op.taskId] = task.copyWith(
              attempts: [...task.attempts, attempt],
            );
          }
        }
      case 'remove_attempt':
        if (task != null) {
          result[op.taskId] = task.copyWith(
            attempts: task.attempts.where((a) => a.id != op.value).toList(),
          );
        }
    }
  }
  return result.values.toList();
}

class SyncTaskStore extends FileTaskStore {
  SyncTaskStore(super.file, this.owner);
  final String owner;
  List<Task> _tasks = [];
  List<MemoOperation> _pending = [];
  bool imported = false;
  List<MemoOperation> get pending => List.unmodifiable(_pending);

  @override
  Future<List<Task>> load() async {
    try {
      _tasks = await super.load();
      _pending = [];
      imported = false;
      if (syncState != null) {
        if (syncState!['owner'] != owner ||
            syncState!['pending'] is! List ||
            syncState!['imported'] is! bool) {
          throw const FormatException('Invalid account sync state');
        }
        _pending = (syncState!['pending'] as List)
            .map(
              (v) =>
                  MemoOperation.fromJson(Map<String, dynamic>.from(v as Map)),
            )
            .toList();
        if (_pending.map((o) => o.id).toSet().length != _pending.length) {
          throw const FormatException('Duplicate pending change');
        }
        imported = syncState!['imported'] as bool;
      } else if (_tasks.isNotEmpty) {
        throw const FormatException('Missing account sync state');
      }
      return _tasks;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> _commit(
    List<Task> tasks,
    List<MemoOperation> pending, {
    bool? didImport,
  }) async {
    await super.saveState(tasks, {
      'owner': owner,
      'pending': pending.map((o) => o.toJson()).toList(),
      'imported': didImport ?? imported,
    });
    _tasks = tasks;
    _pending = pending;
    imported = didImport ?? imported;
  }

  @override
  Future<void> save(List<Task> tasks) =>
      _commit(tasks, [..._pending, ...changesBetween(_tasks, tasks)]);

  Future<List<Task>> merge(List<Task> remote, Set<String> acknowledged) async {
    final remaining = _pending
        .where((o) => !acknowledged.contains(o.id))
        .toList();
    final merged = replay(remote, remaining);
    await _commit(merged, remaining);
    return merged;
  }

  Future<List<Task>> importLocal(List<Task> local) async {
    if (imported) return _tasks;
    final merged = {for (final task in _tasks) task.id: task};
    for (final task in local) {
      final existing = merged[task.id];
      if (existing == null) {
        merged[task.id] = task;
      } else {
        final ids = existing.attempts.map((a) => a.id).toSet();
        merged[task.id] = existing.copyWith(
          attempts: [
            ...existing.attempts,
            ...task.attempts.where((a) => !ids.contains(a.id)),
          ],
        );
      }
    }
    final tasks = merged.values.toList();
    await _commit(tasks, [
      ..._pending,
      ...changesBetween(_tasks, tasks),
    ], didImport: true);
    return tasks;
  }
}
