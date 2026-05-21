import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/tabby_theme.dart';

class ActivityTab extends ConsumerWidget {
  const ActivityTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // v0.2 wiring: stream from `activity_events` filtered by groups the user
    // belongs to, denormalized via the `payload` jsonb column for fast render.
    return Scaffold(
      appBar: AppBar(
        title: Text('Activity',
            style: Theme.of(context).textTheme.displaySmall),
        toolbarHeight: 72,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timeline, size: 48, color: TabbyTheme.teal),
              const SizedBox(height: 12),
              Text("Nothing's happened yet.",
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Expenses and settlements will show up here as they happen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: TabbyTheme.dim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
