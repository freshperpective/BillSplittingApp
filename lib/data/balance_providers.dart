import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/split_engine.dart';
import 'expenses_repository.dart';
import 'groups_repository.dart';
import 'settlements_repository.dart';
import 'supabase_client.dart';

// Per-user providers watch `authStateProvider` so cached AsyncValue from a
// prior signed-in user doesn't leak into the new user's view. See the same
// pattern in groups_repository.dart.

/// Settlements scoped to one group. Kept as its own provider so the
/// group balance can be recomputed (via `ref.invalidate`) when a settlement
/// is added without re-fetching expenses.
final groupSettlementsProvider =
    FutureProvider.family<List<Settlement>, String>((ref, groupId) async {
  ref.watch(authStateProvider);
  return ref.watch(settlementsRepositoryProvider).listForGroup(groupId);
});

/// Net per-profile balance plus a simplified payment plan for a single group.
class GroupBalance {
  const GroupBalance({
    required this.netByProfile,
    required this.transfers,
  });

  /// `profileId → signed net`. Positive = others owe this profile.
  /// `Σ value == 0` by construction (less rounding noise from settlements,
  /// which the calculator handles).
  final Map<String, Decimal> netByProfile;

  /// Minimum-transfer plan: `(debtor → creditor : amount)` rows.
  final List<({String from, String to, Decimal amount})> transfers;

  /// Convenience: my net balance in this group.
  Decimal myNet(String myId) => netByProfile[myId] ?? Decimal.zero;

  /// Convenience: the transfers that involve me (either side).
  List<({String from, String to, Decimal amount})> myTransfers(String myId) {
    return transfers
        .where((t) => t.from == myId || t.to == myId)
        .toList();
  }
}

/// Per-group balance: pulls expenses + settlements, runs the calculator.
///
/// Reads (not watches) the underlying providers so reads can `await` cleanly
/// while still re-triggering when invalidated upstream — group_detail invokes
/// `ref.invalidate(groupBalanceProvider(groupId))` after edits.
final groupBalanceProvider =
    FutureProvider.family<GroupBalance, String>((ref, groupId) async {
  ref.watch(authStateProvider);
  // Watch both upstream providers so invalidating either (after add-expense
  // or add-settlement) cascades into a fresh balance computation.
  final expenses =
      await ref.watch(groupExpensesProvider(groupId).future);
  final settlements =
      await ref.watch(groupSettlementsProvider(groupId).future);

  const calc = BalanceCalculator();
  final net = calc.compute(expenses: expenses, settlements: settlements);
  final transfers = calc.simplify(net);
  return GroupBalance(netByProfile: net, transfers: transfers);
});

/// One peer + my signed net balance with them, aggregated across all groups.
///
/// Positive amount = peer owes me. Negative = I owe peer.
class PeerBalance {
  const PeerBalance({
    required this.peer,
    required this.amount,
  });

  final Profile peer;
  final Decimal amount;

  bool get peerOwesMe => amount > Decimal.zero;
  Decimal get magnitude => amount.abs();
}

/// Cross-group rollup: my net with every peer I share a group with.
///
/// For v0.2 we assume a single currency (the user's default). Mixing
/// currencies will need explicit normalization in v0.3.
final balancesRollupProvider =
    FutureProvider<List<PeerBalance>>((ref) async {
  ref.watch(authStateProvider);
  final me = ref.watch(currentUserProvider);
  if (me == null) return const <PeerBalance>[];

  final groups = await ref.watch(myGroupsProvider.future);
  if (groups.isEmpty) return const <PeerBalance>[];

  // Per-peer running totals (signed, from my perspective).
  final netByPeer = <String, Decimal>{};
  // Profile cache so we can render names without a second lookup pass.
  final profileById = <String, Profile>{};

  for (final g in groups) {
    final members =
        await ref.watch(groupMembersProvider(g.id).future);
    for (final m in members) {
      profileById[m.id] = m;
    }
    final balance = await ref.watch(groupBalanceProvider(g.id).future);
    for (final t in balance.transfers) {
      if (t.from == me.id) {
        // I'm paying peer t.to in this group → I owe them.
        netByPeer[t.to] =
            (netByPeer[t.to] ?? Decimal.zero) - t.amount;
      } else if (t.to == me.id) {
        // Peer t.from is paying me → they owe me.
        netByPeer[t.from] =
            (netByPeer[t.from] ?? Decimal.zero) + t.amount;
      }
      // Transfers that don't involve me are ignored — they're between
      // other members and only matter for *their* rollups.
    }
  }

  final result = <PeerBalance>[];
  for (final entry in netByPeer.entries) {
    if (entry.value == Decimal.zero) continue;
    final peer = profileById[entry.key];
    if (peer == null) continue; // missing profile data → skip
    result.add(PeerBalance(peer: peer, amount: entry.value));
  }

  // Show people who owe me first (largest debt), then people I owe.
  result.sort((a, b) {
    if (a.peerOwesMe != b.peerOwesMe) {
      return a.peerOwesMe ? -1 : 1;
    }
    return b.magnitude.compareTo(a.magnitude);
  });

  return result;
});

/// One concrete settle option between the current user and a peer, scoped
/// to a single group. Comes from the same simplified-transfer view that the
/// per-group balance strip uses, so the math matches everywhere.
class PeerSettleOption {
  const PeerSettleOption({
    required this.group,
    required this.fromProfileId,
    required this.toProfileId,
    required this.amount,
  });

  final Group group;
  final String fromProfileId;
  final String toProfileId;
  final Decimal amount;
}

/// Per-group settle options for a given peer, from my perspective.
///
/// For each group I share with the peer, we look at the simplified transfers
/// and pick out the one (if any) that's between me and them. Groups where
/// the simplifier paired me with someone else are skipped — those aren't
/// settleable bilaterally without re-routing.
final peerSettleOptionsProvider =
    FutureProvider.family<List<PeerSettleOption>, String>((ref, peerId) async {
  ref.watch(authStateProvider);
  final me = ref.watch(currentUserProvider);
  if (me == null) return const <PeerSettleOption>[];

  final groups = await ref.watch(myGroupsProvider.future);

  final options = <PeerSettleOption>[];
  for (final g in groups) {
    final balance = await ref.watch(groupBalanceProvider(g.id).future);
    for (final t in balance.transfers) {
      final involvesUs = (t.from == me.id && t.to == peerId) ||
          (t.from == peerId && t.to == me.id);
      if (!involvesUs) continue;
      options.add(PeerSettleOption(
        group: g,
        fromProfileId: t.from,
        toProfileId: t.to,
        amount: t.amount,
      ));
    }
  }
  // Biggest amount first so the picker leads with the chunk most worth
  // squaring up.
  options.sort((a, b) => b.amount.compareTo(a.amount));
  return options;
});
