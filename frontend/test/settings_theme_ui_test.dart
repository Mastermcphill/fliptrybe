import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fliptrybe/screens/settings_demo_screen.dart';
import 'package:fliptrybe/services/settings_service.dart';
import 'package:fliptrybe/ui/theme/theme_controller.dart';

class _FakeSettingsService extends SettingsService {
  _FakeSettingsService(this._settings);

  final Map<String, dynamic> _settings;

  @override
  Future<Map<String, dynamic>> getSettings() async {
    return Map<String, dynamic>.from(_settings);
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
    if (notifInApp != null) _settings['notif_in_app'] = notifInApp;
    if (notifSms != null) _settings['notif_sms'] = notifSms;
    if (notifWhatsapp != null) _settings['notif_whatsapp'] = notifWhatsapp;
    if (darkMode != null) _settings['dark_mode'] = darkMode;
    if (themeMode != null) _settings['theme_mode'] = themeMode;
    if (backgroundPalette != null)
      _settings['background_palette'] = backgroundPalette;
    return true;
  }
}

void main() {
  testWidgets('Settings screen updates theme controller mode and palette',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'system',
      'background_palette': 'neutral',
    });
    final fake = _FakeSettingsService({
      'notif_in_app': true,
      'notif_sms': false,
      'notif_whatsapp': false,
      'dark_mode': false,
      'theme_mode': 'system',
      'background_palette': 'neutral',
    });
    final controller = ThemeController(settingsService: fake);
    await controller.load();

    await tester.pumpWidget(
      ThemeControllerProvider(
        controller: controller,
        child: MaterialApp(
          home: SettingsDemoScreen(settingsService: fake),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Theme: System'), findsOneWidget);
    expect(find.text('Palette: Neutral'), findsOneWidget);

    await tester.tap(find.text('Theme: System'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme: Dark').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Palette: Neutral'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Palette: Sand').last);
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.backgroundPalette, AppBackgroundPalette.sand);
  });
}
