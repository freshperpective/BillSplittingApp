import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../data/activity_repository.dart';
import '../../data/balance_providers.dart';
import '../../data/expenses_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/receipts_repository.dart';
import '../../data/supabase_client.dart';
import '../theme/tabby_theme.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.groupId,
    required this.expenseId,
  });

  final String groupId;
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(groupExpensesProvider(groupId));
    final members = ref.watch(groupMembersProvider(groupId));
    final me = ref.watch(currentUserProvider);

    // Resolve the expense up-front (rather than inside `expenses.when`) so
    // the AppBar can show creator-only actions without nesting another
    // layer of `.when()`.
    final expense = expenses.valueOrNull
        ?.where((e) => e.id == expenseId)
        .cast<Expense?>()
        .firstWhere((_) => true, orElse: () => null);
    final isCreator = expense != null && me?.id == expense.createdBy;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/group/$groupId')),
        title: const Text('Expense'),
        actions: [
          if (isCreator)
            _ExpenseActionsMenu(
              expense: expense,
              groupId: groupId,
            ),
        ],
      ),
      body: expenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          if (expense == null) {
            return const _MissingExpense();
          }
          return members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Could not load members: $e')),
            data: (memberList) => _ExpenseDetailBody(
              expense: expense,
              members: memberList,
              isCreator: isCreator,
            ),
          );
        },
      ),
    );
  }
}

/// Creator-only AppBar actions. Lives as its own widget so the dialog and
/// async flow are encapsulated; the parent screen just decides whether to
/// show it. Today this is just Delete — Edit will join when the design
/// conversation around split-mode round-tripping lands.
class _ExpenseActionsMenu extends ConsumerWidget {
  const _ExpenseActionsMenu({
    required this.expense,
    required this.groupId,
  });

  final Expense expense;
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Expense actions',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            context.go(
                '/group/$groupId/expense/${expense.id}/edit');
            break;
          case 'delete':
            await _confirmDelete(context, ref);
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 18),
            SizedBox(width: 12),
            Text('Edit expense'),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 18, color: TabbyTheme.clay),
            SizedBox(width: 12),
            Text('Delete expense',
                style: TextStyle(color: TabbyTheme.clay)),
          ]),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text(
          'It will disappear from the group, balances will recalculate, '
          'and the activity feed will record the removal. '
          'Existing settlements stay put.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: TabbyTheme.clay),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(expensesRepositoryProvider).softDelete(expense.id);
      // Server-side trigger logs an expense.delete event automatically;
      // we just need to refresh the read surfaces.
      ref.invalidate(groupExpensesProvider(groupId));
      ref.invalidate(groupBalanceProvider(groupId));
      ref.invalidate(balancesRollupProvider);
      ref.invalidate(activityFeedProvider);
      ref.invalidate(groupActivityProvider(groupId));

      if (context.mounted) {
        context.go('/group/$groupId');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense deleted.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't delete: $e")),
        );
      }
    }
  }
}

class _ExpenseDetailBody extends StatelessWidget {
  const _ExpenseDetailBody({
    required this.expense,
    required this.members,
    required this.isCreator,
  });

  final Expense expense;
  final List<Profile> members;
  final bool isCreator;

  String _name(String profileId) {
    for (final m in members) {
      if (m.id == profileId) return m.displayName;
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final payerShares =
        expense.shares.where((s) => s.paidShare > Decimal.zero).toList();
    final payerLabel = payerShares.length == 1
        ? _name(payerShares.first.profileId)
        : '${payerShares.length} people';
    final dateFmt = DateFormat.yMMMMd();
    // createdAt vs paidAt are different things: paidAt is the date of the
    // expense itself, createdAt is when it was logged into Tabby. Both are
    // useful in audits ("was this entered late?") so we show both.
    final createdFmt = DateFormat.yMMMd().add_jm();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // Header card: amount, description, date.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: TabbyTheme.amber.withOpacity(0.14),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expense.description,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${expense.currency} ${expense.amount}',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: TabbyTheme.teal,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 16, color: TabbyTheme.dim),
                  const SizedBox(width: 4),
                  Text('Paid by $payerLabel',
                      style: const TextStyle(
                          color: TabbyTheme.dim, fontSize: 13)),
                  const SizedBox(width: 16),
                  const Icon(Icons.event,
                      size: 16, color: TabbyTheme.dim),
                  const SizedBox(width: 4),
                  Text(dateFmt.format(expense.paidAt),
                      style: const TextStyle(
                          color: TabbyTheme.dim, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.schedule_outlined,
                      size: 14, color: TabbyTheme.dim),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Added ${createdFmt.format(expense.createdAt.toLocal())} '
                      'by ${_name(expense.createdBy)}',
                      style: const TextStyle(
                          color: TabbyTheme.dim, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Receipts — horizontally scrollable photo strip. Only shown when
        // there are photos OR the viewer is the creator (can add some).
        // The strip manages its own async state via expenseReceiptsProvider.
        _ReceiptStrip(expenseId: expense.id, isCreator: isCreator),
        const SizedBox(height: 20),
        Text('Breakdown',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        // Per-member rows showing what each person paid and owes.
        ...expense.shares.map((share) {
          final net = share.paidShare - share.owedShare;
          final isPositive = net > Decimal.zero;
          final isZero = net == Decimal.zero;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: TabbyTheme.amber.withOpacity(0.4),
                  child: Text(
                    _name(share.profileId).isNotEmpty
                        ? _name(share.profileId)
                            .substring(0, 1)
                            .toUpperCase()
                        : '?',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: TabbyTheme.teal),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_name(share.profileId),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        'Owes ${expense.currency} ${share.owedShare}',
                        style: const TextStyle(
                            color: TabbyTheme.dim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  isZero
                      ? '—'
                      : (isPositive ? '+' : '−') +
                          expense.currency +
                          ' ' +
                          net.abs().toString(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isZero
                        ? TabbyTheme.dim
                        : (isPositive
                            ? TabbyTheme.teal
                            : TabbyTheme.clay),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Receipt strip — photo thumbnails + add/remove affordances
// ---------------------------------------------------------------------------

/// Horizontally scrollable strip of receipt thumbnails for one expense.
///
/// Shows nothing when there are no receipts and the viewer isn't the creator
/// (no point showing an empty section to members who can't add anything).
/// The strip is a ConsumerStatefulWidget so it can manage upload state and
/// invalidate the provider after mutations without bubbling state up.
///
/// iOS note: add NSPhotoLibraryUsageDescription to ios/Runner/Info.plist.
/// Android: READ_MEDIA_IMAGES (API 33+) or READ_EXTERNAL_STORAGE is handled
/// by the image_picker plugin; no manual permission request needed.
class _ReceiptStrip extends ConsumerStatefulWidget {
  const _ReceiptStrip({required this.expenseId, required this.isCreator});

  final String expenseId;
  final bool isCreator;

  @override
  ConsumerState<_ReceiptStrip> createState() => _ReceiptStripState();
}

class _ReceiptStripState extends ConsumerState<_ReceiptStrip> {
  bool _uploading = false;
  String? _uploadError;

  Future<void> _pickAndUpload() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Cap at 1920px on either side — still plenty for a receipt but cuts
      // down transfer time noticeably on modern phone cameras.
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return; // user cancelled

    final bytes = await picked.readAsBytes();
    final mimeType = _mimeFromPath(picked.path);

    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      await ref.read(receiptsRepositoryProvider).upload(
            expenseId: widget.expenseId,
            bytes: bytes,
            mimeType: mimeType,
          );
      ref.invalidate(expenseReceiptsProvider(widget.expenseId));
    } catch (e) {
      if (mounted) {
        setState(() =>
            _uploadError = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmDelete(Receipt receipt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: const Text("It'll be gone permanently."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: TabbyTheme.clay),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(receiptsRepositoryProvider)
          .delete(receipt.storagePath);
      ref.invalidate(expenseReceiptsProvider(widget.expenseId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't remove: $e")),
        );
      }
    }
  }

  void _openViewer(Receipt receipt) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  receipt.signedUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _mimeFromPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'heic' || 'heif' => 'image/heic',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  @override
  Widget build(BuildContext context) {
    final receiptsAsync =
        ref.watch(expenseReceiptsProvider(widget.expenseId));

    return receiptsAsync.when(
      // While loading: take up no vertical space so the breakdown section
      // doesn't jitter downward when receipts resolve.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (receipts) {
        final canAdd =
            widget.isCreator && receipts.length < ReceiptsRepository.maxPerExpense;
        // Hide the section entirely if there's nothing to show and the user
        // can't add anything (i.e. non-creator viewing an expense without photos).
        if (receipts.isEmpty && !widget.isCreator) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  'Receipts',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (_uploading) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 88,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ...receipts.map(
                    (r) => _ReceiptThumbnail(
                      receipt: r,
                      isCreator: widget.isCreator,
                      onTap: () => _openViewer(r),
                      onDelete: () => _confirmDelete(r),
                    ),
                  ),
                  if (canAdd)
                    _AddPhotoButton(
                      uploading: _uploading,
                      onTap: _uploading ? null : _pickAndUpload,
                    ),
                ],
              ),
            ),
            if (_uploadError != null) ...[
              const SizedBox(height: 6),
              Text(
                _uploadError!,
                style: const TextStyle(
                    color: TabbyTheme.clay, fontSize: 12),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ReceiptThumbnail extends StatelessWidget {
  const _ReceiptThumbnail({
    required this.receipt,
    required this.isCreator,
    required this.onTap,
    required this.onDelete,
  });

  final Receipt receipt;
  final bool isCreator;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                receipt.signedUrl,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: 80,
                    height: 80,
                    color: TabbyTheme.amber.withOpacity(0.15),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: TabbyTheme.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: TabbyTheme.dim,
                  ),
                ),
              ),
            ),
            // Delete button — always visible for creator so it's
            // discoverable without needing a long-press hint.
            if (isCreator)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({required this.uploading, required this.onTap});

  final bool uploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: TabbyTheme.amber.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: TabbyTheme.amber.withOpacity(0.40),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              color: uploading ? TabbyTheme.dim : TabbyTheme.amber,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              'Add',
              style: TextStyle(
                fontSize: 11,
                color: uploading ? TabbyTheme.dim : TabbyTheme.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingExpense extends StatelessWidget {
  const _MissingExpense();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline,
                size: 48, color: TabbyTheme.dim),
            const SizedBox(height: 12),
            Text("Couldn't find that expense.",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'It may have been deleted. Go back to refresh the list.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TabbyTheme.dim),
            ),
          ],
        ),
      ),
    );
  }
}
