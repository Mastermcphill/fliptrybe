import 'api_client.dart';
import 'api_config.dart';

class OrderService {
  final ApiClient _client = ApiClient.instance;

  Future<Map<String, dynamic>?> createOrder({
    int? listingId,
    required int merchantId,
    required double amount,
    double deliveryFee = 0,
    String pickup = '',
    String dropoff = '',
    String paymentReference = '',
  }) async {
    final payload = <String, dynamic>{
      'merchant_id': merchantId,
      'amount': amount,
      'delivery_fee': deliveryFee,
      'pickup': pickup,
      'dropoff': dropoff,
      'payment_reference': paymentReference,
      if (listingId != null) 'listing_id': listingId,
    };

    try {
      final res = await _client.dio.post(ApiConfig.api('/orders'), data: payload);
      final data = res.data;
      if (data is Map && data['order'] is Map) return Map<String, dynamic>.from(data['order'] as Map);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> myOrders({int? userId}) async {
    try {
      final suffix = (userId != null) ? '?buyer_id=$userId' : '';
      final res = await _client.dio.get(ApiConfig.api('/orders/my$suffix'));
      return (res.data is List) ? (res.data as List) : <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<List<dynamic>> merchantOrders() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/merchant/orders'));
      return (res.data is List) ? (res.data as List) : <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>?> getOrder(int orderId) async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/orders/$orderId'));
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> timeline(int orderId) async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/orders/$orderId/timeline'));
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> getDelivery(int orderId) async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/orders/$orderId/delivery'));
      if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<bool> merchantAccept(int orderId) async {
    try {
      final res = await _client.dio.post(ApiConfig.api('/orders/$orderId/merchant/accept'));
      final statusCode = res.statusCode ?? 0;
      return statusCode >= 200 && statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> assignDriver(int orderId, int driverId) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/orders/$orderId/driver/assign'),
        data: {'driver_id': driverId},
      );
      final statusCode = res.statusCode ?? 0;
      return statusCode >= 200 && statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> driverSetStatus(int orderId, String status, {String? code}) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/orders/$orderId/driver/status'),
        data: {
          'status': status,
          if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
        },
      );
      final statusCode = res.statusCode ?? 0;
      return statusCode >= 200 && statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> issueQr(int orderId, String step) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/orders/$orderId/qr/issue'),
        data: {'step': step},
      );
      return {
        'ok': (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300,
        'status': res.statusCode ?? 0,
        'data': res.data,
      };
    } catch (e) {
      return {'ok': false, 'status': 0, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> scanQr(int orderId, String token) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/orders/$orderId/qr/scan'),
        data: {'token': token},
      );
      return {
        'ok': (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300,
        'status': res.statusCode ?? 0,
        'data': res.data,
      };
    } catch (e) {
      return {'ok': false, 'status': 0, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> sellerConfirmPickup(int orderId, String code) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/seller/orders/$orderId/confirm-pickup'),
        data: {'code': code.trim()},
      );
      return {
        'ok': (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300,
        'status': res.statusCode ?? 0,
        'data': res.data,
      };
    } catch (e) {
      return {'ok': false, 'status': 0, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> driverConfirmDelivery(int orderId, String code) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/driver/orders/$orderId/confirm-delivery'),
        data: {'code': code.trim()},
      );
      return {
        'ok': (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300,
        'status': res.statusCode ?? 0,
        'data': res.data,
      };
    } catch (e) {
      return {'ok': false, 'status': 0, 'error': e.toString()};
    }
  }

  Future<bool> buyerConfirmDelivery(int orderId, String code) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/orders/$orderId/buyer/confirm'),
        data: {'code': code.trim()},
      );
      final status = res.statusCode ?? 0;
      return status >= 200 && status < 300;
    } catch (_) {
      return false;
    }
  }
}
