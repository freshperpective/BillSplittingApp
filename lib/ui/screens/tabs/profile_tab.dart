import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models.dart';
import '../../../data/profiles_repository.dart';
import '../../../data/supabase_client.dart';
import '../../theme/tabby_theme.dart';

/// "Me" tab — shows the signed-in user's profile and lets them edit
/// display name and default currency. Avatar uploads land here once
/// Supabase Storage is wired up alongside receipts.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(myProfileProvider);
    final email = user?.email ?? '—';

    return Scaffold(
      appBar: AppBar(
        title: Text('Me', style: Theme.of(context).textTheme.displaySmall),
        toolbarHeight: 72,
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text("Couldn't load profile: $e"),
          ),
        ),
        data: (profile) => _ProfileBody(
          profile: profile,
          email: email,
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile, required this.email});

  final Profile? profile;
  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = profile?.displayName ?? '—';
    final currency = profile?.defaultCurrency ?? 'INR';
    final initial = name.isNotEmpty && name != '—'
        ? name.substring(0, 1).toUpperCase()
        : '?';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // Identity card.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: TabbyTheme.amber.withOpacity(0.4),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: TabbyTheme.teal,
                      fontWeight: FontWeight.w600,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style:
                              Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(email,
                          style: TextStyle(
                              color: TabbyTheme.dimOf(context), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Editable fields.
        _SettingsTile(
          icon: Icons.badge_outlined,
          title: 'Display name',
          subtitle: name,
          onTap: () => _editName(context, ref, current: profile?.displayName),
        ),
        _SettingsTile(
          icon: Icons.payments_outlined,
          title: 'Default currency',
          subtitle: currency,
          onTap: () => _editCurrency(context, ref, current: currency),
        ),

        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () async {
            await ref.read(supabaseClientProvider).auth.signOut();
            // myProfileProvider re-evaluates on auth change, so no
            // explicit invalidate needed here.
          },
          icon: const Icon(Icons.logout, color: TabbyTheme.clay),
          label: const Text('Sign out',
              style: TextStyle(color: TabbyTheme.clay)),
        ),
      ],
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref,
      {String? current}) async {
    final controller = TextEditingController(text: current ?? '');
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final inset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Display name',
                  style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'What other members see next to your expenses.',
                style: TextStyle(color: TabbyTheme.dimOf(context), fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'e.g. Aman',
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, controller.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: TabbyTheme.teal,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (saved == null || saved.isEmpty || saved == current) return;
    await _commit(context, ref, () async {
      await ref
          .read(profilesRepositoryProvider)
          .updateMine(displayName: saved);
    });
  }

  Future<void> _editCurrency(BuildContext context, WidgetRef ref,
      {required String current}) async {
    // Hardcoded set matches the new-group sheet so the two surfaces
    // can't drift. Expand here when we add proper currency selection.
    const currencies = ['INR', 'USD', 'EUR', 'GBP', 'JPY', 'AUD', 'CAD', 'SGD'];
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Default currency'),
        children: [
          for (final c in currencies)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Row(
                children: [
                  if (c == current)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.check,
                          size: 18, color: TabbyTheme.teal),
                    )
                  else
                    const SizedBox(width: 26),
                  Text(c,
                      style: TextStyle(
                        fontWeight: c == current
                            ? FontWeight.w600
                            : FontWeight.normal,
                      )),
                ],
              ),
            ),
        ],
      ),
    );

    if (picked == null || picked == current) return;
    await _commit(context, ref, () async {
      await ref
          .read(profilesRepositoryProvider)
          .updateMine(defaultCurrency: picked);
    });
  }

  /// Shared save flow: run the update, invalidate, surface either a
  /// success snackbar or the raw error. The body is a callback so the
  /// caller can compose whichever update path it needs.
  Future<void> _commit(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() body,
  ) async {
    try {
      await body();
      ref.invalidate(myProfileProvider);
      // Group lists show display names — bump those too so the change
      // shows up in the Members sheet and the per-expense payer label.
      // (We invalidate by family-key only if we knew which groups had
      // the user; cheapest is to leave the read providers alone — they
      // re-pull on next viewport open.)
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Updated.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't update: $e")),
        );
      }
    }
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: TabbyTheme.teal),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Icon(Icons.chevron_right, color: TabbyTheme.dimOf(context)),
        onTap: onTap,
      ),
    );
  }
}
