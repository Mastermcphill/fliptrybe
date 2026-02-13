import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fliptrybe/services/settings_service.dart';
import 'package:fliptrybe/ui/theme/theme_controller.dart';

class _FakeSettingsService extends SettingsService {
  _FakeSettingsService({
    Map<String, dynamic>? initial,
  }) : _state = Map<String, dynamic>.from(initial ?? <String, dynamic>{});

  final Map<String, dynamic> _state;

  @override
  Future<Map<String, dynamic>> getSettings() async {
    return Map<String, dynamic>.from(_state);
  }

  @override
  Future<bool> updateSettings({
    bool? notifInApp,
    bool? notifSms,
    bool? notifWhatsapp,
    bool? darkMode,
    String? themeMode,
    String? backgroundPalette,
  }) async {
    if (notifInApp != null) _state['notif_in_app'] = notifInApp;
    if (notifSms != null) _state['notif_sms'] = notifSms;
    if (notifWhatsapp != null) _state['notif_whatsapp'] = notifWhatsapp;
    if (darkMode != null) _state['dark_mode'] = darkMode;
    if (themeMode != null) _state['theme_mode'] = themeMode;
    if (backgroundPalette != null) _state['background_palette'] = backgroundPalette;
    return true;
  }
}

void main() {
  test('ThemeController loads persisted values and updates state', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'background_palette': 'mint',
    });
    final fake = _FakeSettingsService(initial: {
      'theme_mode': 'dark',
      'background_palette': 'mint',
      'notif_in_app': true,
      'notif_sms': false,
      'notif_whatsapp': false,
    });
    final controller = ThemeController(settingsService: fake);
    await controller.load();

    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.backgroundPalette, AppBackgroundPalette.mint);

    await controller.setThemeMode(ThemeMode.light);
    await controller.setBackgroundPalette(AppBackgroundPalette.sand);
    expect(controller.themeMode, ThemeMode.light);
    expect(controller.backgroundPalette, AppBackgroundPalette.sand);
  });
}
