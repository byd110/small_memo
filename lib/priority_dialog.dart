import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'task.dart';
import 'task_controller.dart';

class PriorityDialog extends StatefulWidget {
  const PriorityDialog({
    super.key,
    required this.task,
    required this.controller,
  });
  final Task task;
  final TaskController controller;
  @override
  State<PriorityDialog> createState() => _PriorityDialogState();
}

class _PriorityDialogState extends State<PriorityDialog> {
  late final _number = TextEditingController(
    text: widget.task.priority?.toString() ?? '1',
  );
  late bool _unclassified = widget.task.priority == null;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final number = int.tryParse(_number.text);
    if (!_unclassified && (number == null || !Task.validPriority(number))) {
      setState(
        () => _error = 'Enter a whole number from 1 to ${Task.maxPriority}.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.controller.setPriority(
      widget.task.id,
      _unclassified ? null : number,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = 'Could not save the priority. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set priority'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Unclassified'),
            value: _unclassified,
            onChanged: _saving
                ? null
                : (v) => setState(() => _unclassified = v!),
          ),
          TextField(
            controller: _number,
            enabled: !_unclassified && !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 10,
            decoration: const InputDecoration(
              labelText: 'Priority number',
              helperText: '1 is most important',
            ),
            onSubmitted: (_) {
              if (!_saving) _save();
            },
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
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
