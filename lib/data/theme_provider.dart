import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme { system, light, grey, dark }

extension AppThemeExtension on AppTheme {
  String get label => switch (this) {
        AppTheme.system => 'System default',
        AppTheme.light => 'Light',
        AppTheme.grey => 'Grey',
        AppTheme.dark => 'Dark',
      };

  ThemeMode get themeMode => switch (this) {
        AppTheme.system => ThemeMode.system,
        AppTheme.light => ThemeMode.light,
        AppTheme.grey => ThemeMode.light,
        AppTheme.dark => ThemeMode.dark,
      };
}

const _kPrefKey = 'app_theme';

class ThemeNotifier extends Notifier<AppTheme> {
  @override
  AppTheme build() {
    _load();
    return AppTheme.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefKey);
    if (saved != null) {
      final match = AppTheme.values.where((t) => t.name == saved).firstOrNull;
      if (match != null) state = match;
    }
  }

  Future<void> set(AppTheme theme) async {
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, theme.name);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, AppTheme>(
  ThemeNotifier.new,
);
