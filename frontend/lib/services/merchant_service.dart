import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_config.dart';

class MerchantService {
  MerchantService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<List<dynamic>> getLeaderboard() async {
    try {
      final res =
          await _client.dio.get(ApiConfig.api('/leaderboards') + '?limit=50');
      final data = res.data;
      final items = (data is Map && data['items'] is List)
          ? (data['items'] as List)
          : <dynamic>[];
      return items.map((raw) {
        if (raw is! Map) return <String, dynamic>{};
        final m = Map<String, dynamic>.from(raw);
        return <String, dynamic>{
          'user_id': m['user_id'],
          'name': (m['shop_name'] ?? '').toString().trim().isEmpty
              ? 'Merchant #${m['user_id'] ?? '-'}'
              : (m['shop_name'] ?? '').toString(),
          'score': m['score'] ?? 0,
          'orders': m['total_orders'] ?? 0,
          'listings': m['listings_count'] ?? 0,
          'revenue_gross': m['total_sales'] ?? 0,
          'state': m['state'] ?? '',
          'city': m['city'] ?? '',
        };
      }).toList();
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> getKpis() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/kpis/merchant'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<List<dynamic>> topMerchants({int limit = 20}) async {
    try {
      final res = await _client.dio
          .get(ApiConfig.api('/merchants/top') + '?limit=$limit');
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> merchantDetail(int userId) async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/merchants/$userId'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> publicMerchantCard(int userId) async {
    try {
      final res =
          await _client.dio.get(ApiConfig.api('/public/merchants/$userId'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> followMerchant(int userId) async {
    try {
      final res =
          await _client.dio.post(ApiConfig.api('/merchants/$userId/follow'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> unfollowMerchant(int userId) async {
    try {
      final res =
          await _client.dio.delete(ApiConfig.api('/merchants/$userId/follow'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> followStatus(int userId) async {
    try {
      final res = await _client.dio
          .get(ApiConfig.api('/merchants/$userId/follow-status'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false, 'following': false};
    } catch (_) {
      return <String, dynamic>{'ok': false, 'following': false};
    }
  }

  Future<Map<String, dynamic>> followersCount(int userId) async {
    try {
      final res = await _client.dio
          .get(ApiConfig.api('/merchants/$userId/followers-count'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false, 'followers': 0};
    } catch (_) {
      return <String, dynamic>{'ok': false, 'followers': 0};
    }
  }

  Future<List<Map<String, dynamic>>> myFollowingMerchants(
      {int limit = 50, int offset = 0}) async {
    try {
      final res = await _client.dio.get(
          ApiConfig.api('/me/following-merchants?limit=$limit&offset=$offset'));
      final data = res.data;
      if (data is Map && data['items'] is List) {
        return (data['items'] as List)
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList();
      }
      if (data is List) {
        return data
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList();
      }
      return <Map<String, dynamic>>[];
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> merchantFollowers(
      {int limit = 50, int offset = 0}) async {
    try {
      final res = await _client.dio.get(
          ApiConfig.api('/merchant/followers?limit=$limit&offset=$offset'));
      final data = res.data;
      if (data is Map && data['items'] is List) {
        return (data['items'] as List)
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList();
      }
      return <Map<String, dynamic>>[];
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>> merchantFollowersCount() async {
    try {
      final res =
          await _client.dio.get(ApiConfig.api('/merchant/followers/count'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false, 'followers': 0};
    } catch (_) {
      return <String, dynamic>{'ok': false, 'followers': 0};
    }
  }

  Future<Map<String, dynamic>> addReview(
      {required int userId,
      required int rating,
      required String comment,
      String raterName = 'Anonymous'}) async {
    try {
      final res = await _client.dio
          .post(ApiConfig.api('/merchants/$userId/review'), data: {
        'rating': rating,
        'comment': comment,
        'rater_name': raterName
      });
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    required String shopName,
    required String category,
    required String state,
    required String city,
    String locality = '',
    String lga = '',
  }) async {
    try {
      final res =
          await _client.dio.post(ApiConfig.api('/merchants/profile'), data: {
        'shop_name': shopName,
        'shop_category': category,
        'state': state,
        'city': city,
        'locality': locality,
        'lga': lga,
      });
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> updateProfilePhoto(
      String profileImageUrl) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/me/profile/photo'),
        data: {'profile_image_url': profileImageUrl},
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> cloudinaryConfig() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/media/cloudinary/config'));
      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
    } catch (_) {}
    return <String, dynamic>{'ok': false};
  }

  Future<Map<String, dynamic>> cloudinarySign({
    required int timestamp,
    String folder = '',
    String publicId = '',
  }) async {
    final payload = <String, dynamic>{
      'timestamp': timestamp,
      'resource_type': 'image',
    };
    if (folder.trim().isNotEmpty) {
      payload['folder'] = folder.trim();
    }
    if (publicId.trim().isNotEmpty) {
      payload['public_id'] = publicId.trim();
    }
    try {
      final res =
          await _client.dio.post(ApiConfig.api('/media/cloudinary/sign'), data: payload);
      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
    } catch (_) {}
    return <String, dynamic>{'ok': false};
  }

  Future<Map<String, dynamic>> updateProfilePhotoFromFile(String filePath) async {
    try {
      final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final cfg = await cloudinaryConfig();
      final cloudName = (cfg['cloud_name'] ?? '').toString().trim();
      final folder = (cfg['folder'] ?? 'fliptrybe/merchant_profiles').toString();
      if (cloudName.isNotEmpty) {
        final sign = await cloudinarySign(
          timestamp: nowTs,
          folder: folder,
          publicId: 'merchant_${DateTime.now().millisecondsSinceEpoch}',
        );
        final signature = (sign['signature'] ?? '').toString().trim();
        final apiKey = (sign['api_key'] ?? '').toString().trim();
        final signedCloudName = (sign['cloud_name'] ?? cloudName).toString().trim();
        final signedFolder = (sign['folder'] ?? folder).toString().trim();
        final signedPublicId = (sign['public_id'] ?? '').toString().trim();
        if (signature.isNotEmpty &&
            apiKey.isNotEmpty &&
            signedCloudName.isNotEmpty &&
            signedPublicId.isNotEmpty) {
          final form = FormData.fromMap({
            'file': await MultipartFile.fromFile(filePath),
            'api_key': apiKey,
            'timestamp': nowTs.toString(),
            'signature': signature,
            'folder': signedFolder,
            'public_id': signedPublicId,
          });
          final uploadRes = await _client.dio.post(
            'https://api.cloudinary.com/v1_1/$signedCloudName/image/upload',
            data: form,
            options: Options(contentType: 'multipart/form-data'),
          );
          final uploadData = uploadRes.data;
          if (uploadData is Map) {
            final secureUrl = (uploadData['secure_url'] ?? '').toString().trim();
            if (secureUrl.isNotEmpty) {
              final saved = await updateProfilePhoto(secureUrl);
              if (saved['ok'] == true) {
                return <String, dynamic>{
                  ...saved,
                  'source': 'cloudinary',
                };
              }
            }
          }
        }
      }
    } catch (_) {}

    try {
      final normalized = filePath.replaceAll('\\', '/');
      final filename = normalized.split('/').last;
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(filePath, filename: filename),
      });
      final res = await _client.dio.post(
        ApiConfig.api('/me/profile/photo'),
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      if (res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
    } catch (_) {}
    return <String, dynamic>{
      'ok': false,
      'message': 'Unable to upload merchant photo.',
    };
  }
}
