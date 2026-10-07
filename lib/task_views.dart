import 'package:flutter/material.dart';
import 'task.dart';
import 'task_controller.dart';

String attemptLabel(int count) =>
    '$count ${count == 1 ? 'attempt' : 'attempts'}';
String stampLabel(BuildContext context, DateTime stamp) {
  final local = stamp.toLocal();
  final l = MaterialLocalizations.of(context);
  final seconds = local.second.toString().padLeft(2, '0');
  return '${l.formatMediumDate(local)} · ${l.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}:$seconds';
}

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, required this.controller});
  final Task task;
  final TaskController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: task.done,
              semanticLabel: task.title,
              onChanged: controller.busy
                  ? null
                  : (_) => controller.toggle(task.id),
            ),
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontSize: 16,
                  color: task.done ? Colors.grey.shade600 : null,
                  decoration: task.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Task options for ${task.title}',
              enabled: !controller.busy,
              onSelected: (value) async {
                if (value == 'edit') {
                  await showDialog<void>(
                    context: context,
                    builder: (_) =>
                        EditTaskDialog(task: task, controller: controller),
                  );
                } else {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete task?'),
                      content: Text(
                        'Delete “${task.title}” and all ${attemptLabel(task.attempts.length)}? This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await controller.delete(task.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit description')),
                PopupMenuItem(value: 'delete', child: Text('Delete task')),
              ],
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: controller.busy
                    ? null
                    : () => controller.recordAttempt(task.id),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Log attempt'),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AttemptHistoryPage(
                      taskId: task.id,
                      controller: controller,
                    ),
                  ),
                ),
                child: Text(attemptLabel(task.attempts.length)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class EditTaskDialog extends StatefulWidget {
  const EditTaskDialog({
    super.key,
    required this.task,
    required this.controller,
  });
  final Task task;
  final TaskController controller;
  @override
  State<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog> {
  late final _text = TextEditingController(text: widget.task.title);
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Enter a description.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.controller.edit(widget.task.id, _text.text);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = 'Could not save. Your changes are still here; try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit description'),
    content: TextField(
      controller: _text,
      autofocus: true,
      enabled: !_saving,
      maxLength: 500,
      minLines: 1,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: 'Description',
        errorText: _error,
        errorMaxLines: 3,
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}

class AttemptHistoryPage extends StatelessWidget {
  const AttemptHistoryPage({
    super.key,
    required this.taskId,
    required this.controller,
  });
  final String taskId;
  final TaskController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final task = controller.tasks.where((t) => t.id == taskId).firstOrNull;
      final attempts = [...?task?.attempts]
        ..sort((a, b) => b.at.compareTo(a.at));
      return Scaffold(
        appBar: AppBar(title: const Text('Attempt history')),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(task?.title ?? 'Task deleted'),
              ),
              Text(
                '${attemptLabel(attempts.length)} · Times shown in your local timezone',
              ),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: attempts.isEmpty
                    ? const Center(child: Text('No attempts yet.'))
                    : ListView.builder(
                        itemCount: attempts.length,
                        itemBuilder: (context, index) {
                          final attempt = attempts[index];
                          return ListTile(
                            title: Text(stampLabel(context, attempt.at)),
                            trailing: IconButton(
                              tooltip: 'Remove attempt',
                              icon: const Icon(Icons.undo),
                              onPressed: controller.busy
                                  ? null
                                  : () async {
                                      final yes = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text(
                                            'Remove this attempt?',
                                          ),
                                          content: Text(
                                            stampLabel(context, attempt.at),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Remove'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (yes == true) {
                                        await controller.removeAttempt(
                                          taskId,
                                          attempt.id,
                                        );
                                      }
                                    },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key, required this.controller});
  final TaskController controller;
  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  String _period = '7';
  DateTimeRange? _custom;

  Future<void> _select(String? value) async {
    if (value == null) return;
    if (value == 'custom') {
      final now = DateTime.now();
      final timestamps = widget.controller.tasks
          .expand((t) => t.attempts)
          .map((a) => a.at.toLocal());
      var first = DateTime(now.year - 10);
      var last = DateTime(now.year + 1, 12, 31);
      for (final at in timestamps) {
        if (at.isBefore(first)) first = DateTime(at.year, at.month, at.day);
        if (at.isAfter(last)) last = DateTime(at.year, at.month, at.day);
      }
      final range = await showDateRangePicker(
        context: context,
        firstDate: first,
        lastDate: last,
        initialDateRange: _custom,
        helpText: 'Count attempts on these dates',
      );
      if (!mounted || range == null) return;
      setState(() {
        _custom = range;
        _period = value;
      });
    } else {
      setState(() => _period = value);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Attempt summary')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          DateTime? start;
          DateTime? end;
          if (_period == 'custom') {
            start = _custom!.start;
            final last = _custom!.end;
            end = DateTime(last.year, last.month, last.day + 1);
          } else if (_period != 'all') {
            start = DateTime(
              today.year,
              today.month,
              today.day - int.parse(_period) + 1,
            );
            end = DateTime(today.year, today.month, today.day + 1);
          }
          final rows =
              [
                for (final task in widget.controller.tasks)
                  (task: task, count: task.attemptsBetween(start, end)),
              ]..sort((a, b) {
                final count = b.count.compareTo(a.count);
                return count != 0
                    ? count
                    : a.task.title.compareTo(b.task.title);
              });
          final total = rows.fold(0, (sum, row) => sum + row.count);
          final l = MaterialLocalizations.of(context);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Period'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _period,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: '1', child: Text('Today')),
                            DropdownMenuItem(
                              value: '7',
                              child: Text('Last 7 days'),
                            ),
                            DropdownMenuItem(
                              value: '30',
                              child: Text('Last 30 days'),
                            ),
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('All time'),
                            ),
                            DropdownMenuItem(
                              value: 'custom',
                              child: Text('Custom dates…'),
                            ),
                          ],
                          onChanged: _select,
                        ),
                      ),
                    ),
                    if (_period == 'custom')
                      TextButton(
                        onPressed: () => _select('custom'),
                        child: Text(
                          '${l.formatMediumDate(_custom!.start)} – ${l.formatMediumDate(_custom!.end)}',
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      '${attemptLabel(total)} total',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Includes completed tasks. Dates use your local timezone.',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('No tasks yet.'))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return ListTile(
                            title: Text(row.task.title),
                            subtitle: Text(
                              row.task.done ? 'Completed' : 'Open',
                            ),
                            trailing: Text(attemptLabel(row.count)),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => AttemptHistoryPage(
                                  taskId: row.task.id,
                                  controller: widget.controller,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
