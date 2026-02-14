import '../utils/ft_logger.dart';

class AnalyticsHooks {
  AnalyticsHooks._();

  static final AnalyticsHooks instance = AnalyticsHooks._();

  Future<void> track(
    String eventName, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) async {
    FTLogger.logInfo('analytics', eventName, context: properties);
  }

  Future<void> loginSuccess({required String role}) =>
      track('login_success', properties: {'role': role});

  Future<void> signupSuccess({required String role}) =>
      track('signup_success', properties: {'role': role});

  Future<void> listingView({required int listingId}) =>
      track('listing_view', properties: {'listing_id': listingId});

  Future<void> listingContact({required int listingId}) =>
      track('listing_contact', properties: {'listing_id': listingId});

  Future<void> orderCreated({required int orderId}) =>
      track('order_created', properties: {'order_id': orderId});

  Future<void> withdrawalInitiated({required String source, double? amount}) =>
      track('withdrawal_initiated', properties: {
        'source': source,
        if (amount != null) 'amount': amount,
      });

  Future<void> paymentSuccess({required String channel, String? reference}) =>
      track('payment_success', properties: {
        'channel': channel,
        if (reference != null && reference.trim().isNotEmpty)
          'reference': reference,
      });

  Future<void> paymentFail({required String channel, String? reason}) =>
      track('payment_fail', properties: {
        'channel': channel,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason,
      });
}
