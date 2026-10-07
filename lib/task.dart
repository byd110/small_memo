class Task {
  const Task({required this.id, required this.title, this.done = false});

  final String id;
  final String title;
  final bool done;

  Task toggled() => Task(id: id, title: title, done: !done);

  Map<String, Object> toJson() => {'id': id, 'title': title, 'done': done};

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
    return Task(id: id, title: title, done: done);
  }
}
