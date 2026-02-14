import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../ui/theme/theme_controller.dart';

class SettingsDemoScreen extends StatefulWidget {
  const SettingsDemoScreen({super.key, this.settingsService});

  final SettingsService? settingsService;

  @override
  State<SettingsDemoScreen> createState() => _SettingsDemoScreenState();
}

class _SettingsDemoScreenState extends State<SettingsDemoScreen> {
  late final SettingsService _svc;

  bool notifInApp = true;
  bool notifSms = false;
  bool notifWhatsapp = false;
  bool darkMode = false;
  String _themeMode = 'system';
  String _backgroundPalette = 'neutral';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _svc = widget.settingsService ?? SettingsService();
    _load();
  }

  Future<void> _load() async {
    final s = await _svc.getSettings();
    if (!mounted) return;
    final theme = ThemeControllerProvider.maybeOf(context);
    setState(() {
      notifInApp = (s['notif_in_app'] == true);
      notifSms = (s['notif_sms'] == true);
      notifWhatsapp = (s['notif_whatsapp'] == true);
      darkMode = (s['dark_mode'] == true);
      _themeMode = s['theme_mode']?.toString() ??
          themeModeToRaw(theme?.themeMode ?? ThemeMode.system);
      _backgroundPalette = s['background_palette']?.toString() ??
          (theme?.backgroundPalette.value ??
              AppBackgroundPalette.neutral.value);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final theme = ThemeControllerProvider.maybeOf(context);
    if (theme != null) {
      await theme.setThemeMode(themeModeFromRaw(_themeMode));
      await theme.setBackgroundPalette(
          AppBackgroundPalette.fromRaw(_backgroundPalette));
    }
    await _svc.updateSettings(
      notifInApp: notifInApp,
      notifSms: notifSms,
      notifWhatsapp: notifWhatsapp,
      darkMode: darkMode,
      themeMode: _themeMode,
      backgroundPalette: _backgroundPalette,
    );
  }

  Future<void> _toggle(void Function() apply) async {
    setState(apply);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('In-app notifications'),
                  value: notifInApp,
                  onChanged: (v) => _toggle(() => notifInApp = v),
                ),
                SwitchListTile(
                  title: const Text('SMS alerts (demo-ready)'),
                  subtitle: const Text(
                      'Persisted to backend. Add Termii/NG SMS later.'),
                  value: notifSms,
                  onChanged: (v) => _toggle(() => notifSms = v),
                ),
                SwitchListTile(
                  title: const Text('WhatsApp alerts (demo-ready)'),
                  subtitle: const Text(
                      'Persisted to backend. Add WhatsApp Cloud later.'),
                  value: notifWhatsapp,
                  onChanged: (v) => _toggle(() => notifWhatsapp = v),
                ),
                const Divider(height: 26),
                Text(
                  'Appearance',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
                SwitchListTile(
                  title: const Text('Dark mode (legacy compatibility)'),
                  value: darkMode,
                  onChanged: (v) => _toggle(() => darkMode = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _themeMode,
                  items: const [
                    DropdownMenuItem(
                        value: 'system', child: Text('Theme: System')),
                    DropdownMenuItem(
                        value: 'light', child: Text('Theme: Light')),
                    DropdownMenuItem(value: 'dark', child: Text('Theme: Dark')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _toggle(() => _themeMode = value);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _backgroundPalette,
                  items: const [
                    DropdownMenuItem(
                        value: 'neutral', child: Text('Palette: Neutral')),
                    DropdownMenuItem(
                        value: 'mint', child: Text('Palette: Mint')),
                    DropdownMenuItem(
                        value: 'sand', child: Text('Palette: Sand')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _toggle(() => _backgroundPalette = value);
                  },
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Persistence enabled',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Theme mode and palette are synced to backend and cached locally.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
