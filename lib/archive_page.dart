import 'package:flutter/material.dart';

import 'task_controller.dart';
import 'task_views.dart';

class ArchivePage extends StatelessWidget {
  const ArchivePage({super.key, required this.controller});
  final TaskController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Archive')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tasks = controller.tasks.where((t) => t.archived).toList()
          ..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Finished tasks are archived after 30 days. Their descriptions and attempt history are kept. Uncheck a task to reopen it in its original priority group.',
            ),
            const SizedBox(height: 16),
            if (controller.error != null)
              Text(
                controller.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (tasks.isEmpty) const Text('No archived tasks.'),
            for (final task in tasks) ...[
              TaskTile(task: task, controller: controller),
              Text(
                'Archived ${stampLabel(context, task.archivedAt!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    ),
  );
}
