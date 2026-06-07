import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/theme_provider.dart';
import 'ui/router.dart';
import 'ui/theme/sorted_theme.dart';

class SortedApp extends ConsumerWidget {
  const SortedApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final appTheme = ref.watch(themeProvider);
    return MaterialApp.router(
      title: 'Sorted',
      debugShowCheckedModeBanner: false,
      theme: appTheme == AppTheme.grey ? SortedTheme.grey() : SortedTheme.light(),
      darkTheme: SortedTheme.dark(),
      themeMode: appTheme.themeMode,
      routerConfig: router,
    );
  }
}
