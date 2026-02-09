import 'package:dio/dio.dart';
import 'api_client.dart';
import 'api_config.dart';

class ShortletService {
  ShortletService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<List<dynamic>> listShortlets({
    String state = '',
    String city = '',
    String locality = '',
    String lga = '',
    double? lat,
    double? lng,
    double radiusKm = 10,
  }) async {
    final qp = <String>[];
    if (state.trim().isNotEmpty) qp.add('state=${Uri.encodeComponent(state.trim())}');
    if (city.trim().isNotEmpty) qp.add('city=${Uri.encodeComponent(city.trim())}');
    if (locality.trim().isNotEmpty) qp.add('locality=${Uri.encodeComponent(locality.trim())}');
    if (lga.trim().isNotEmpty) qp.add('lga=${Uri.encodeComponent(lga.trim())}');
    if (lat != null) qp.add('lat=${lat.toString()}');
    if (lng != null) qp.add('lng=${lng.toString()}');
    if (radiusKm > 0) qp.add('radius_km=${radiusKm.toString()}');

    final suffix = qp.isEmpty ? '' : '?${qp.join('&')}';
    final url = ApiConfig.api('/shortlets') + suffix;

    try {
      final res = await _client.dio.get(url);
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return <dynamic>[];
      final data = res.data;
      if (data is List) return data;
      if (data is Map) {
        final items = data['items'];
        if (items is List) return items;
      }
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<bool> createShortlet({
    required String title,
    required String description,
    required String nightlyPrice,
    required String imagePath,
    String state = '',
    String city = '',
    String locality = '',
    String lga = '',
    String beds = '1',
    String baths = '1',
    String guests = '2',
    String cleaningFee = '0',
    String availableFrom = '',
    String availableTo = '',
    double? latitude,
    double? longitude,
  }) async {
    try {
      final safeTitle = title.trim();
      if (safeTitle.isEmpty) return false;

      String filename = 'shortlet.jpg';
      final safeImagePath = imagePath.trim();
      if (safeImagePath.isNotEmpty) {
        final parts = safeImagePath.split(RegExp(r'[\\/]+'));
        final last = parts.isNotEmpty ? parts.last.trim() : '';
        if (last.isNotEmpty) filename = last;
      }

      final form = FormData.fromMap({
        'title': safeTitle,
        'description': description.trim(),
        'nightly_price': nightlyPrice.trim(),
        'cleaning_fee': cleaningFee.trim(),
        'beds': beds.trim(),
        'baths': baths.trim(),
        'guests': guests.trim(),
        if (state.trim().isNotEmpty) 'state': state.trim(),
        if (city.trim().isNotEmpty) 'city': city.trim(),
        if (locality.trim().isNotEmpty) 'locality': locality.trim(),
        if (lga.trim().isNotEmpty) 'lga': lga.trim(),
        if (availableFrom.trim().isNotEmpty) 'available_from': availableFrom.trim(),
        if (availableTo.trim().isNotEmpty) 'available_to': availableTo.trim(),
        if (latitude != null) 'latitude': latitude.toString(),
        if (longitude != null) 'longitude': longitude.toString(),
        if (safeImagePath.isNotEmpty)
          'image': await MultipartFile.fromFile(safeImagePath, filename: filename),
      });

      final res = await _client.dio.post(
        ApiConfig.api('/shortlets'),
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );

      final code = res.statusCode ?? 0;
      return code == 200 || code == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitReview({required int shortletId, required double rating}) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/shortlets/$shortletId/review'),
        data: {'rating': rating},
      );
      final code = res.statusCode ?? 0;
      return code == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> bookShortlet({
    required int shortletId,
    required String checkIn,
    required String checkOut,
    String guestName = '',
    String guestPhone = '',
  }) async {
    final payload = {
      'check_in': checkIn.trim(),
      'check_out': checkOut.trim(),
      'guest_name': guestName.trim(),
      'guest_phone': guestPhone.trim(),
    };

    try {
      final res = await _client.dio.post(ApiConfig.api('/shortlets/$shortletId/book'), data: payload);
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<List<dynamic>> popularShortlets() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/shortlets/popular'));
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return <dynamic>[];
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      if (data is List) return data;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> getShortlet(int shortletId) async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/shortlets/$shortletId'));
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return <String, dynamic>{};
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

}
