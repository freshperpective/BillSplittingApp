import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/activity_repository.dart';
import '../../../data/supabase_client.dart';
import '../../theme/tabby_theme.dart';
import '../../widgets/activity_row.dart';

class ActivityTab extends ConsumerWidget {
  const ActivityTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(activityFeedProvider);
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Activity',
            style: Theme.of(context).textTheme.displaySmall),
        toolbarHeight: 72,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(activityFeedProvider),
          ),
        ],
      ),
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text("Couldn't load activity: $e"),
          ),
        ),
        data: (feed) {
          if (feed.events.isEmpty) return const _EmptyState();
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(activityFeedProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: feed.events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => ActivityRow(
                event: feed.events[i],
                feed: feed,
                myId: me?.id,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: TabbyTheme.amber.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.timeline,
                  size: 36, color: TabbyTheme.amber),
            ),
            const SizedBox(height: 20),
            Text("Nothing's happened yet.",
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Expenses, member adds, and settle-ups will show up here as they happen.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: TabbyTheme.dim),
            ),
          ],
        ),
      ),
    );
  }
}
