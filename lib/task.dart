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
    List<Attempt> attempts = const [],
  }) : _attempts = attempts;

  final String id;
  final String title;
  final bool done;
  final List<Attempt> _attempts;
  List<Attempt> get attempts => List.unmodifiable(_attempts);

  Task copyWith({String? title, bool? done, List<Attempt>? attempts}) => Task(
    id: id,
    title: title ?? this.title,
    done: done ?? this.done,
    attempts: List.unmodifiable(attempts ?? _attempts),
  );
  Task toggled() => copyWith(done: !done);

  /// Calendar dates in the viewer's local timezone; end is exclusive.
  int attemptsBetween(DateTime? start, DateTime? end) => _attempts
      .where(
        (a) =>
            (start == null || !a.at.isBefore(start)) &&
            (end == null || a.at.isBefore(end)),
      )
      .length;

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'done': done,
    'attempts': _attempts.map((a) => a.toJson()).toList(),
  };

  factory Task.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final done = json['done'];
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
      attempts: List.unmodifiable(attempts),
    );
  }
}
