import 'package:dio/dio.dart';
import 'api_client.dart';
import 'api_config.dart';

class ShortletService {
  ShortletService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;
  static List<Map<String, dynamic>> _cachedShortlets = <Map<String, dynamic>>[];
  static DateTime? _cachedAt;

  DateTime? get cachedAt => _cachedAt;

  List<Map<String, dynamic>> cachedShortlets() {
    return _cachedShortlets
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

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
    if (state.trim().isNotEmpty) {
      qp.add('state=${Uri.encodeComponent(state.trim())}');
    }
    if (city.trim().isNotEmpty) {
      qp.add('city=${Uri.encodeComponent(city.trim())}');
    }
    if (locality.trim().isNotEmpty) {
      qp.add('locality=${Uri.encodeComponent(locality.trim())}');
    }
    if (lga.trim().isNotEmpty) {
      qp.add('lga=${Uri.encodeComponent(lga.trim())}');
    }
    if (lat != null) {
      qp.add('lat=${lat.toString()}');
    }
    if (lng != null) {
      qp.add('lng=${lng.toString()}');
    }
    if (radiusKm > 0) {
      qp.add('radius_km=${radiusKm.toString()}');
    }

    final suffix = qp.isEmpty ? '' : '?${qp.join('&')}';
    final url = ApiConfig.api('/shortlets') + suffix;

    try {
      final res = await _client.dio.get(url);
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return <dynamic>[];
      final data = res.data;
      if (data is List) {
        final items = data
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        if (items.isNotEmpty) {
          _cachedShortlets = items;
          _cachedAt = DateTime.now().toUtc();
        }
        return data;
      }
      if (data is Map) {
        final items = data['items'];
        if (items is List) {
          final mapped = items
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false);
          if (mapped.isNotEmpty) {
            _cachedShortlets = mapped;
            _cachedAt = DateTime.now().toUtc();
          }
          return items;
        }
      }
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<List<dynamic>> recommendedShortlets({
    String city = '',
    String state = '',
    int limit = 20,
  }) async {
    final qp = <String>[];
    if (city.trim().isNotEmpty) {
      qp.add('city=${Uri.encodeComponent(city.trim())}');
    }
    if (state.trim().isNotEmpty) {
      qp.add('state=${Uri.encodeComponent(state.trim())}');
    }
    qp.add('limit=${limit < 1 ? 20 : limit > 60 ? 60 : limit}');
    final suffix = qp.isEmpty ? '' : '?${qp.join('&')}';
    try {
      final res = await _client.dio
          .get(ApiConfig.api('/public/shortlets/recommended$suffix'));
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return <dynamic>[];
      final data = res.data;
      if (data is Map && data['items'] is List) {
        final items = (data['items'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        if (items.isNotEmpty) {
          _cachedShortlets = items;
          _cachedAt = DateTime.now().toUtc();
        }
        return data['items'] as List;
      }
      if (data is List) {
        final items = data
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        if (items.isNotEmpty) {
          _cachedShortlets = items;
          _cachedAt = DateTime.now().toUtc();
        }
        return data;
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
    List<Map<String, dynamic>> media = const <Map<String, dynamic>>[],
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
        if (availableFrom.trim().isNotEmpty)
          'available_from': availableFrom.trim(),
        if (availableTo.trim().isNotEmpty) 'available_to': availableTo.trim(),
        if (latitude != null) 'latitude': latitude.toString(),
        if (longitude != null) 'longitude': longitude.toString(),
        if (safeImagePath.isNotEmpty)
          'image':
              await MultipartFile.fromFile(safeImagePath, filename: filename),
        if (media.isNotEmpty) 'media': media,
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

  Future<bool> submitReview(
      {required int shortletId, required double rating}) async {
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
    int guests = 1,
    String paymentMethod = 'wallet',
  }) async {
    final payload = {
      'check_in': checkIn.trim(),
      'check_out': checkOut.trim(),
      'guest_name': guestName.trim(),
      'guest_phone': guestPhone.trim(),
      'guests': guests,
      'payment_method': paymentMethod,
    };

    try {
      final res = await _client.dio
          .post(ApiConfig.api('/shortlets/$shortletId/book'), data: payload);
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
      final res =
          await _client.dio.get(ApiConfig.api('/shortlets/$shortletId'));
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return <String, dynamic>{};
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> favoriteShortlet(int shortletId) async {
    try {
      final res = await _client.dio
          .post(ApiConfig.api('/shortlets/$shortletId/favorite'));
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> unfavoriteShortlet(int shortletId) async {
    try {
      final res = await _client.dio
          .delete(ApiConfig.api('/shortlets/$shortletId/favorite'));
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> recordView(int shortletId,
      {String sessionKey = ''}) async {
    try {
      final payload = <String, dynamic>{};
      if (sessionKey.trim().isNotEmpty) {
        payload['session_key'] = sessionKey.trim();
      }
      final res = await _client.dio
          .post(ApiConfig.api('/shortlets/$shortletId/view'), data: payload);
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> cloudinaryConfig() async {
    try {
      final res =
          await _client.dio.get(ApiConfig.api('/media/cloudinary/config'));
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> cloudinarySign({
    int timestamp = 0,
    String folder = '',
    String publicId = '',
    String resourceType = 'auto',
  }) async {
    final payload = <String, dynamic>{
      'timestamp': timestamp > 0
          ? timestamp
          : DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'resource_type': resourceType,
    };
    if (folder.trim().isNotEmpty) {
      payload['folder'] = folder.trim();
    }
    if (publicId.trim().isNotEmpty) {
      payload['public_id'] = publicId.trim();
    }
    try {
      final res = await _client.dio
          .post(ApiConfig.api('/media/cloudinary/sign'), data: payload);
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> attachMedia({
    required int shortletId,
    required String mediaType,
    required String url,
    String thumbnailUrl = '',
    int durationSeconds = 0,
    int position = 0,
  }) async {
    final payload = <String, dynamic>{
      'media_type': mediaType,
      'url': url,
      'thumbnail_url': thumbnailUrl,
      'duration_seconds': durationSeconds,
      'position': position,
    };
    try {
      final res = await _client.dio
          .post(ApiConfig.api('/shortlets/$shortletId/media'), data: payload);
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }
}
