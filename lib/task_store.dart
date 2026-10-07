import 'dart:convert';
import 'dart:io';

import 'task.dart';

abstract interface class TaskStore {
  Future<List<Task>> load();
  Future<void> save(List<Task> tasks);
}

/// Owns an OS lock for its lifetime so two app processes cannot overwrite data.
/// Each save flushes a sibling temporary file before atomically replacing data.
class FileTaskStore implements TaskStore {
  FileTaskStore(this.file);

  final File file;
  RandomAccessFile? _lock;
  bool _loaded = false;
  int _version = 2;

  @override
  Future<List<Task>> load() async {
    if (_loaded) throw StateError('Store already loaded');
    await file.parent.create(recursive: true);
    final lock = await File('${file.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } catch (_) {
      await lock.close();
      throw const FileSystemException(
        'Could not lock the task file. Another Small Memo may be running.',
      );
    }
    _lock = lock;
    try {
      final tasks = <Task>[];
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is! Map<String, dynamic> ||
            (data['version'] != 1 && data['version'] != 2) ||
            data['tasks'] is! List) {
          throw const FormatException('Unrecognized task file');
        }
        _version = data['version'] as int;
        final ids = <String>{};
        for (final item in data['tasks'] as List) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Invalid task');
          }
          if (_version == 2 && item['attempts'] is! List) {
            throw const FormatException('Missing attempt history');
          }
          final task = Task.fromJson(item);
          if (!ids.add(task.id)) {
            throw const FormatException('Duplicate task ID');
          }
          tasks.add(task);
        }
      }
      _loaded = true;
      return tasks;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  @override
  Future<void> save(List<Task> tasks) async {
    if (!_loaded || _lock == null) throw StateError('Store is not loaded');
    if (_version == 1) {
      final backup = File('${file.path}.v1.bak');
      if (!await backup.exists()) await file.copy(backup.path);
    }
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 2,
        'tasks': tasks.map((task) => task.toJson()).toList(),
      }),
      flush: true,
    );
    await temporary.rename(file.path);
    _version = 2;
  }

  Future<void> close() async {
    final lock = _lock;
    _lock = null;
    _loaded = false;
    if (lock != null) await lock.close();
  }
}
