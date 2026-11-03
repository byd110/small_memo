import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'deadline.dart';

String deadlineDateLabel(BuildContext context, Deadline deadline) {
  final date = deadline.wallTime;
  final l = MaterialLocalizations.of(context);
  final time = l.formatTimeOfDay(
    TimeOfDay.fromDateTime(date),
    alwaysUse24HourFormat: true,
  );
  return '${l.formatMediumDate(date)} · $time ${deadline.abbreviation}';
}

String deadlineStatus(Deadline deadline, bool done, DateTime now) {
  if (done) return 'Deadline';
  if (!now.isBefore(deadline.at)) return 'Overdue';
  final localNow = tz.TZDateTime.from(now, Deadline.location(deadline.zone));
  final due = deadline.wallTime;
  final days = DateTime.utc(due.year, due.month, due.day)
      .difference(DateTime.utc(localNow.year, localNow.month, localNow.day))
      .inDays;
  return days == 0
      ? 'Due today'
      : days == 1
      ? 'Due tomorrow'
      : 'Due';
}

class DeadlineLabel extends StatelessWidget {
  const DeadlineLabel({super.key, required this.deadline, required this.done});
  final Deadline deadline;
  final bool done;
  @override
  Widget build(BuildContext context) {
    final status = deadlineStatus(deadline, done, DateTime.now());
    final color = status == 'Overdue'
        ? Theme.of(context).colorScheme.error
        : !done && (status == 'Due today' || status == 'Due tomorrow')
        ? Theme.of(context).colorScheme.primary
        : null;
    return Text(
      '$status · ${deadlineDateLabel(context, deadline)}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
    );
  }
}

class DeadlineDialog extends StatefulWidget {
  const DeadlineDialog({super.key, this.initial, required this.onSave});
  final Deadline? initial;
  final Future<bool> Function(Deadline?) onSave;
  @override
  State<DeadlineDialog> createState() => _DeadlineDialogState();
}

class _DeadlineDialogState extends State<DeadlineDialog> {
  late String _zone = widget.initial?.zone ?? Deadline.defaultZone;
  late DateTime _date =
      widget.initial?.wallTime ?? tz.TZDateTime.now(Deadline.location(_zone));
  late TimeOfDay _time = widget.initial == null
      ? const TimeOfDay(hour: 17, minute: 0)
      : TimeOfDay.fromDateTime(widget.initial!.wallTime);
  DateTime? _occurrence;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _occurrence = widget.initial?.at;
  }

  List<DateTime> get _candidates =>
      Deadline.candidates(_zone, _date, _time.hour, _time.minute);
  void _change(VoidCallback change) => setState(() {
    change();
    _occurrence = null;
    _error = null;
  });

  Future<void> _save({bool remove = false}) async {
    if (_saving) return;
    final matches = _candidates;
    if (!remove &&
        (matches.isEmpty ||
            (matches.length > 1 && !matches.contains(_occurrence)))) {
      setState(
        () => _error = matches.isEmpty
            ? 'That time is skipped by daylight saving. Choose a different time.'
            : 'That time happens twice. Choose which occurrence you mean.',
      );
      return;
    }
    final value = remove
        ? null
        : Deadline(matches.length == 1 ? matches.single : _occurrence!, _zone);
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.onSave(value);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = 'Could not save the deadline. Please try again.';
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year < 1900 ? _date.year : 1900),
      lastDate: DateTime(_date.year > 2100 ? _date.year : 2100, 12, 31),
    );
    if (picked != null && mounted) _change(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) _change(() => _time = picked);
  }

  void _relativeDate(int days) {
    final today = tz.TZDateTime.now(Deadline.location(_zone));
    _change(() => _date = DateTime(today.year, today.month, today.day + days));
  }

  @override
  Widget build(BuildContext context) {
    final matches = _candidates;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Task deadline'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => _relativeDate(0),
                    child: const Text('Today'),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => _relativeDate(1),
                    child: const Text('Tomorrow'),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(
                  MaterialLocalizations.of(context).formatMediumDate(_date),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickTime,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(
                  MaterialLocalizations.of(
                    context,
                  ).formatTimeOfDay(_time, alwaysUse24HourFormat: true),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _zone,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Time zone'),
                items: [
                  for (final entry in Deadline.zones.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => _change(() => _zone = value!),
              ),
              const SizedBox(height: 8),
              Text(
                _zone == 'America/Toronto'
                    ? 'Follows Eastern daylight saving (EST / EDT).'
                    : _zone == 'Etc/GMT+5'
                    ? 'EST stays UTC−5 all year.'
                    : 'UTC stays the same all year.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (matches.length > 1) ...[
                const SizedBox(height: 8),
                const Text('This time happens twice. Choose one:'),
                for (final instant in matches)
                  ChoiceChip(
                    label: Text(
                      '${Deadline(instant, _zone).abbreviation} · ${instant.hour.toString().padLeft(2, '0')}:${instant.minute.toString().padLeft(2, '0')} UTC',
                    ),
                    selected: _occurrence == instant,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _occurrence = instant),
                  ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          if (widget.initial != null)
            TextButton(
              onPressed: _saving ? null : () => _save(remove: true),
              child: const Text('Remove deadline'),
            ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
