import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_config.dart';

class CartService {
  final ApiClient _client = ApiClient.instance;

  Future<Map<String, dynamic>> getCart() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/cart'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false, 'items': <dynamic>[]};
    } catch (_) {
      return <String, dynamic>{'ok': false, 'items': <dynamic>[]};
    }
  }

  Future<Map<String, dynamic>> addItem({
    required int listingId,
    int quantity = 1,
  }) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/cart/items'),
        data: <String, dynamic>{
          'listing_id': listingId,
          'quantity': quantity,
        },
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } on DioException catch (e) {
      if (e.response?.data is Map) {
        return Map<String, dynamic>.from(e.response!.data as Map);
      }
      return <String, dynamic>{
        'ok': false,
        'message': e.message ?? 'Unable to add item',
      };
    } catch (e) {
      return <String, dynamic>{'ok': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> updateItem({
    required int itemId,
    required int quantity,
  }) async {
    try {
      final res = await _client.dio.patch(
        ApiConfig.api('/cart/items/$itemId'),
        data: <String, dynamic>{'quantity': quantity},
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } on DioException catch (e) {
      if (e.response?.data is Map) {
        return Map<String, dynamic>.from(e.response!.data as Map);
      }
      return <String, dynamic>{
        'ok': false,
        'message': e.message ?? 'Unable to update item'
      };
    } catch (e) {
      return <String, dynamic>{'ok': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> removeItem(int itemId) async {
    try {
      final res =
          await _client.dio.delete(ApiConfig.api('/cart/items/$itemId'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } on DioException catch (e) {
      if (e.response?.data is Map) {
        return Map<String, dynamic>.from(e.response!.data as Map);
      }
      return <String, dynamic>{
        'ok': false,
        'message': e.message ?? 'Unable to remove item'
      };
    } catch (e) {
      return <String, dynamic>{'ok': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> checkoutBulk({
    required List<int> listingIds,
    required String paymentMethod,
    required String idempotencyKey,
  }) async {
    final headers = <String, dynamic>{'Idempotency-Key': idempotencyKey};
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/orders/bulk'),
        data: <String, dynamic>{
          'listing_ids': listingIds,
          'payment_method': paymentMethod,
        },
        options: Options(headers: headers),
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{
        'ok': false,
        'message': 'Unexpected checkout response'
      };
    } on DioException catch (e) {
      if (e.response?.data is Map) {
        return Map<String, dynamic>.from(e.response!.data as Map);
      }
      return <String, dynamic>{
        'ok': false,
        'message': e.message ?? 'Checkout failed'
      };
    } catch (e) {
      return <String, dynamic>{'ok': false, 'message': e.toString()};
    }
  }
}
