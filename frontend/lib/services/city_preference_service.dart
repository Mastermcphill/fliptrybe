import 'package:shared_preferences/shared_preferences.dart';

import '../constants/ng_cities.dart';
import 'api_client.dart';
import 'api_config.dart';

class CityPreferenceService {
  static const String _cityKey = 'preferred_city_local';
  static const String _stateKey = 'preferred_state_local';

  Future<Map<String, String>> getLocalPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final city = (prefs.getString(_cityKey) ?? defaultDiscoveryCity).trim();
    final state = (prefs.getString(_stateKey) ?? defaultDiscoveryState).trim();
    return <String, String>{
      'preferred_city': city.isEmpty ? defaultDiscoveryCity : city,
      'preferred_state': state.isEmpty ? defaultDiscoveryState : state,
    };
  }

  Future<void> setLocalPreference({
    required String preferredCity,
    required String preferredState,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final city = preferredCity.trim().isEmpty
        ? defaultDiscoveryCity
        : preferredCity.trim();
    final state = preferredState.trim().isEmpty
        ? defaultDiscoveryState
        : preferredState.trim();
    await prefs.setString(_cityKey, city);
    await prefs.setString(_stateKey, state);
  }

  Future<Map<String, String>> syncFromServer() async {
    final local = await getLocalPreference();
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/me/preferences'));
    if (data is Map && data['ok'] == true && data['preferences'] is Map) {
      final prefs = Map<String, dynamic>.from(data['preferences'] as Map);
      final city = (prefs['preferred_city'] ?? '').toString().trim();
      final state = (prefs['preferred_state'] ?? '').toString().trim();
      if (city.isNotEmpty || state.isNotEmpty) {
        final merged = <String, String>{
          'preferred_city': city.isEmpty ? local['preferred_city']! : city,
          'preferred_state': state.isEmpty ? local['preferred_state']! : state,
        };
        await setLocalPreference(
          preferredCity: merged['preferred_city']!,
          preferredState: merged['preferred_state']!,
        );
        return merged;
      }
    }
    return local;
  }

  Future<Map<String, String>> saveAndSync({
    required String preferredCity,
    required String preferredState,
  }) async {
    await setLocalPreference(
      preferredCity: preferredCity,
      preferredState: preferredState,
    );
    final payload = <String, dynamic>{
      'preferred_city': preferredCity.trim(),
      'preferred_state': preferredState.trim(),
    };
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/me/preferences'),
      payload,
    );
    if (data is Map && data['ok'] == true && data['preferences'] is Map) {
      final prefs = Map<String, dynamic>.from(data['preferences'] as Map);
      final city = (prefs['preferred_city'] ?? preferredCity).toString();
      final state = (prefs['preferred_state'] ?? preferredState).toString();
      await setLocalPreference(preferredCity: city, preferredState: state);
      return <String, String>{'preferred_city': city, 'preferred_state': state};
    }
    return getLocalPreference();
  }
}
