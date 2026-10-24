class Attempt {
  const Attempt({required this.id, required this.at});
  final String id;
  final DateTime at;

  Map<String, Object> toJson() => {
    'id': id,
    'at': at.toUtc().toIso8601String(),
  };

  factory Attempt.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final stamp = json['at'];
    final at = stamp is String ? DateTime.tryParse(stamp) : null;
    if (id is! String ||
        id.isEmpty ||
        at == null ||
        !at.isUtc ||
        at.toIso8601String() != stamp) {
      throw const FormatException('Invalid attempt timestamp');
    }
    return Attempt(id: id, at: at);
  }
}

class Task {
  const Task({
    required this.id,
    required this.title,
    this.done = false,
    this.completedAt,
    this.archivedAt,
    this.priority,
    this.position = 0,
    List<Attempt> attempts = const [],
  }) : _attempts = attempts;

  final String id;
  final String title;
  final bool done;
  final DateTime? completedAt;
  final DateTime? archivedAt;
  bool get archived => archivedAt != null;
  final int? priority;
  final int position;
  static const maxPriority = 2147483647;
  static bool validPriority(Object? value) =>
      value == null || (value is int && value >= 1 && value <= maxPriority);
  final List<Attempt> _attempts;
  List<Attempt> get attempts => List.unmodifiable(_attempts);

  Task copyWith({String? title, bool? done, List<Attempt>? attempts}) => Task(
    id: id,
    title: title ?? this.title,
    done: done ?? this.done,
    completedAt: done == false ? null : completedAt,
    archivedAt: done == false ? null : archivedAt,
    priority: priority,
    position: position,
    attempts: List.unmodifiable(attempts ?? _attempts),
  );
  Task placed(int? priority, int position) => Task(
    id: id,
    title: title,
    done: done,
    completedAt: completedAt,
    archivedAt: archivedAt,
    attempts: _attempts,
    priority: priority,
    position: position,
  );
  Task lifecycle(bool done, DateTime? completedAt, DateTime? archivedAt) =>
      Task(
        id: id,
        title: title,
        priority: priority,
        position: position,
        attempts: _attempts,
        done: done,
        completedAt: done ? completedAt : null,
        archivedAt: done ? archivedAt : null,
      );
  Task toggled() =>
      lifecycle(!done, done ? null : DateTime.now().toUtc(), null);

  /// Calendar dates in the viewer's local timezone; end is exclusive.
  int attemptsBetween(DateTime? start, DateTime? end) => _attempts
      .where(
        (a) =>
            (start == null || !a.at.isBefore(start)) &&
            (end == null || a.at.isBefore(end)),
      )
      .length;

  Map<String, Object?> toJson() => {
    'priority': priority,
    'position': position,
    'id': id,
    'title': title,
    'done': done,
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'archived_at': archivedAt?.toUtc().toIso8601String(),
    'attempts': _attempts.map((a) => a.toJson()).toList(),
  };

  factory Task.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final done = json['done'];
    DateTime? stamp(String key) {
      final value = json[key];
      if (value == null) return null;
      final date = value is String ? DateTime.tryParse(value) : null;
      if (date == null || !date.isUtc || date.toIso8601String() != value) {
        throw FormatException('Invalid $key');
      }
      return date;
    }

    final completedAt = stamp('completed_at');
    final archivedAt = stamp('archived_at');
    if ((done != true && (completedAt != null || archivedAt != null)) ||
        (archivedAt != null && completedAt == null)) {
      throw const FormatException('Invalid task lifecycle');
    }
    final priority = json['priority'];
    final position = json['position'] ?? 0;
    if (!validPriority(priority) ||
        position is! int ||
        position < 0 ||
        position > 2147483647) {
      throw const FormatException('Invalid task placement');
    }
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        done is! bool) {
      throw const FormatException('Invalid task data');
    }
    final raw = json['attempts'] ?? [];
    if (raw is! List) throw const FormatException('Invalid attempt history');
    final attempts = <Attempt>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid attempt');
      }
      final attempt = Attempt.fromJson(item);
      if (!ids.add(attempt.id)) {
        throw const FormatException('Duplicate attempt ID');
      }
      attempts.add(attempt);
    }
    return Task(
      id: id,
      title: title,
      done: done,
      completedAt: completedAt,
      archivedAt: archivedAt,
      priority: priority as int?,
      position: position,
      attempts: List.unmodifiable(attempts),
    );
  }
}

String priorityLabel(int? priority) =>
    priority == null ? 'Unclassified' : 'Priority $priority';

List<Task> orderedTasks(Iterable<Task> tasks) => tasks.toList()
  ..sort((a, b) {
    final group = (a.priority ?? 0).compareTo(b.priority ?? 0);
    if (group != 0) return group;
    final order = a.position.compareTo(b.position);
    return order != 0 ? order : a.id.compareTo(b.id);
  });
