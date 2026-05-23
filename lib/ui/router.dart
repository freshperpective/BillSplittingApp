import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/supabase_client.dart';
import 'screens/auth_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/home_shell.dart';
import 'screens/add_expense_screen.dart';
import 'screens/expense_detail_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final user = ref.read(currentUserProvider);
      final goingToAuth = state.matchedLocation == '/auth';
      if (user == null && !goingToAuth) return '/auth';
      if (user != null && goingToAuth) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (_, __) => const HomeShell(),
        routes: [
          GoRoute(
            path: 'group/:id',
            builder: (_, state) =>
                GroupDetailScreen(groupId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'add',
                builder: (_, state) =>
                    AddExpenseScreen(groupId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'expense/:expenseId',
                builder: (_, state) => ExpenseDetailScreen(
                  groupId: state.pathParameters['id']!,
                  expenseId: state.pathParameters['expenseId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod's auth stream into go_router's refresh contract.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}
