import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsStore {
  Future<void> _persist(SharedPreferences prefs, Future<bool> write) async {
    try {
      if (!await write) throw StateError('Settings could not be saved.');
    } catch (_) {
      // A failed platform write may still change the preferences memory cache.
      try { await prefs.reload(); } catch (_) {}
      rethrow;
    }
  }

  static const _themeKey = 'pdfmate_theme_mode';
  static const _autoSaveKey = 'pdfmate_auto_save_downloads';
  static const _onboardingKey = 'pdfmate_onboarding_complete';

  Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs, prefs.setString(
      _themeKey,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    ));
  }

  Future<bool> loadAutoSaveDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSaveKey) ?? true;
  }

  Future<void> saveAutoSaveDownloads(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs, prefs.setBool(_autoSaveKey, value));
  }

  Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingKey) ?? false;
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs, prefs.setBool(_onboardingKey, true));
  }
}
