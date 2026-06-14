import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式枚举
enum ThemeModeOption {
  system,   // 跟随系统
  light,    // 浅色
  dark,     // 深色
}

/// 主题模式 Provider
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const _key = 'theme_mode';

  ThemeModeNotifier() : super(ThemeMode.system) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_key) ?? 0;
    state = ThemeMode.values[index];
  }

  Future<void> setThemeMode(ThemeModeOption option) async {
    final prefs = await SharedPreferences.getInstance();
    ThemeMode mode;
    switch (option) {
      case ThemeModeOption.system:
        mode = ThemeMode.system;
        break;
      case ThemeModeOption.light:
        mode = ThemeMode.light;
        break;
      case ThemeModeOption.dark:
        mode = ThemeMode.dark;
        break;
    }
    state = mode;
    await prefs.setInt(_key, mode.index);
  }

  ThemeModeOption get currentOption {
    switch (state) {
      case ThemeMode.system:
        return ThemeModeOption.system;
      case ThemeMode.light:
        return ThemeModeOption.light;
      case ThemeMode.dark:
        return ThemeModeOption.dark;
      default:
        return ThemeModeOption.system;
    }
  }
}
