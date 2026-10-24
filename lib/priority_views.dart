import 'dart:async';

import 'package:flutter/material.dart';

import 'task.dart';
import 'task_controller.dart';
import 'task_views.dart';

/// Headers remain stationary in group order; only task handles can start a drag.
class PriorityTaskList extends StatefulWidget {
  const PriorityTaskList({super.key, required this.controller});
  final TaskController controller;
  @override
  State<PriorityTaskList> createState() => _PriorityTaskListState();
}

class _PriorityTaskListState extends State<PriorityTaskList> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  Timer? _autoScroll;
  Offset? _pointer;
  String? _dragged;
  void _endDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _pointer = null;
    if (mounted && _dragged != null) setState(() => _dragged = null);
  }

  void _startDrag(String id) {
    _autoScroll?.cancel();
    setState(() => _dragged = id);
    _autoScroll = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || _pointer == null || !_scroll.hasClients) return;
      final y = box.globalToLocal(_pointer!).dy;
      final delta = y < 48
          ? -12.0
          : y > box.size.height - 48
          ? 12.0
          : 0.0;
      if (delta != 0) {
        _scroll.jumpTo(
          (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Widget _target({
    required int? priority,
    String? beforeId,
    required Widget child,
    required String label,
  }) => DragTarget<String>(
    onWillAcceptWithDetails: (d) =>
        !widget.controller.busy &&
        d.data != beforeId &&
        widget.controller.tasks.any((t) => t.id == d.data),
    onAcceptWithDetails: (d) =>
        widget.controller.move(d.data, priority, beforeId: beforeId),
    builder: (context, candidates, rejected) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (candidates.isNotEmpty)
          Container(height: 3, color: Theme.of(context).colorScheme.primary),
        Semantics(label: label, child: child),
      ],
    ),
  );

  Widget _handle(Task task) => Draggable<String>(
    data: task.id,
    maxSimultaneousDrags: widget.controller.busy || _dragged != null ? 0 : 1,
    onDragStarted: () => _startDrag(task.id),
    onDragEnd: (_) => _endDrag(),
    onDraggableCanceled: (_, _) => _endDrag(),
    feedback: Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 220,
          child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ),
    ),
    child: Tooltip(
      message: 'Drag to reorder or change priority',
      child: SizedBox(
        width: 36,
        height: 48,
        child: Semantics(
          label: 'Drag ${task.title}',
          child: const Icon(Icons.drag_indicator),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tasks = widget.controller.tasks
        .where((t) => !t.done && !t.archived)
        .toList();
    final priorities = <int?>[
      null,
      ...tasks.map((t) => t.priority).whereType<int>().toSet().toList()..sort(),
    ];
    final children = <Widget>[];
    for (final priority in priorities) {
      final group = tasks.where((t) => t.priority == priority).toList();
      final label = priorityLabel(priority);
      children.add(
        _target(
          priority: priority,
          beforeId: group.firstOrNull?.id,
          label: 'Drop at start of $label',
          child: Padding(
            key: ValueKey('group-$priority'),
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
      );
      if (group.isEmpty) {
        children.add(
          _target(
            priority: priority,
            label: 'Drop into $label',
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No unclassified tasks'),
            ),
          ),
        );
      }
      for (final task in group) {
        children.add(
          _target(
            priority: priority,
            beforeId: task.id,
            label: 'Drop before ${task.title}',
            child: Opacity(
              opacity: _dragged == task.id ? 0.4 : 1,
              child: TaskTile(
                key: ValueKey(task.id),
                task: task,
                controller: widget.controller,
                dragHandle: _handle(task),
              ),
            ),
          ),
        );
      }
      if (group.isNotEmpty) {
        children.add(
          _target(
            priority: priority,
            label: 'Drop at end of $label',
            child: SizedBox(
              key: ValueKey('end-$priority'),
              height: _dragged == null ? 12 : 36,
              child: _dragged == null
                  ? null
                  : Center(
                      child: Text(
                        'Move to end of $label',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
            ),
          ),
        );
      }
    }
    final finished = widget.controller.tasks
        .where((t) => t.done && !t.archived)
        .toList();
    if (finished.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Finished',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: widget.controller.busy
                    ? null
                    : widget.controller.archiveAllFinished,
                child: const Text('Archive all'),
              ),
            ],
          ),
        ),
      );
      for (final task in finished) {
        children.add(
          TaskTile(
            key: ValueKey(task.id),
            task: task,
            controller: widget.controller,
          ),
        );
      }
    }
    return Listener(
      onPointerDown: (event) => _pointer = event.position,
      onPointerMove: (event) => _pointer = event.position,
      onPointerUp: (_) => _endDrag(),
      onPointerCancel: (_) => _endDrag(),
      child: ListView(key: _viewport, controller: _scroll, children: children),
    );
  }
}
