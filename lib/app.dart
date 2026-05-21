import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/router.dart';
import 'ui/theme/tabby_theme.dart';

class TabbyApp extends ConsumerWidget {
  const TabbyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Tabby',
      debugShowCheckedModeBanner: false,
      theme: TabbyTheme.light(),
      darkTheme: TabbyTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
