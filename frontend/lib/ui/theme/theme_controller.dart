import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/settings_service.dart';

enum AppBackgroundPalette {
  neutral('neutral'),
  mint('mint'),
  sand('sand');

  const AppBackgroundPalette(this.value);
  final String value;

  static AppBackgroundPalette fromRaw(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    return AppBackgroundPalette.values.firstWhere(
      (item) => item.value == value,
      orElse: () => AppBackgroundPalette.neutral,
    );
  }
}

ThemeMode themeModeFromRaw(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value == 'light') return ThemeMode.light;
  if (value == 'dark') return ThemeMode.dark;
  return ThemeMode.system;
}

String themeModeToRaw(ThemeMode mode) {
  if (mode == ThemeMode.light) return 'light';
  if (mode == ThemeMode.dark) return 'dark';
  return 'system';
}

class ThemeController extends ChangeNotifier {
  ThemeController({SettingsService? settingsService})
      : _settingsService = settingsService ?? SettingsService();

  static const _prefsThemeMode = 'theme_mode';
  static const _prefsBackgroundPalette = 'background_palette';

  final SettingsService _settingsService;

  ThemeMode _themeMode = ThemeMode.system;
  AppBackgroundPalette _backgroundPalette = AppBackgroundPalette.neutral;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  AppBackgroundPalette get backgroundPalette => _backgroundPalette;
  bool get loaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = themeModeFromRaw(prefs.getString(_prefsThemeMode));
    _backgroundPalette = AppBackgroundPalette.fromRaw(
      prefs.getString(_prefsBackgroundPalette),
    );
    _loaded = true;
    notifyListeners();

    try {
      final settings = await _settingsService.getSettings();
      final remoteMode = themeModeFromRaw(settings['theme_mode']?.toString());
      final remotePalette = AppBackgroundPalette.fromRaw(
        settings['background_palette']?.toString(),
      );
      _themeMode = remoteMode;
      _backgroundPalette = remotePalette;
      await prefs.setString(_prefsThemeMode, themeModeToRaw(_themeMode));
      await prefs.setString(_prefsBackgroundPalette, _backgroundPalette.value);
      notifyListeners();
    } catch (_) {
      // Keep local preferences when remote sync is unavailable.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsThemeMode, themeModeToRaw(mode));
    unawaited(_syncRemote());
  }

  Future<void> setBackgroundPalette(AppBackgroundPalette palette) async {
    _backgroundPalette = palette;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBackgroundPalette, palette.value);
    unawaited(_syncRemote());
  }

  Future<void> _syncRemote() async {
    Map<String, dynamic> current = const <String, dynamic>{};
    try {
      current = await _settingsService.getSettings();
    } catch (_) {}
    await _settingsService.updateSettings(
      notifInApp: current['notif_in_app'] == true,
      notifSms: current['notif_sms'] == true,
      notifWhatsapp: current['notif_whatsapp'] == true,
      darkMode: _themeMode == ThemeMode.dark,
      themeMode: themeModeToRaw(_themeMode),
      backgroundPalette: _backgroundPalette.value,
    );
  }
}

class ThemeControllerProvider extends InheritedNotifier<ThemeController> {
  const ThemeControllerProvider({
    super.key,
    required ThemeController controller,
    required Widget child,
  }) : super(notifier: controller, child: child);

  static ThemeController of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ThemeControllerProvider>();
    if (provider?.notifier == null) {
      throw StateError('ThemeControllerProvider not found in widget tree.');
    }
    return provider!.notifier!;
  }

  static ThemeController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ThemeControllerProvider>()
        ?.notifier;
  }
}
