import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class FTLogger {
  FTLogger._();

  static void logInfo(String tag, String message,
      {Map<String, Object?> context = const {}}) {
    _log('INFO', tag, message, context: context);
  }

  static void logWarn(String tag, String message,
      {Map<String, Object?> context = const {}}) {
    _log('WARN', tag, message,
        context: context, sentryLevel: SentryLevel.warning);
  }

  static void logError(String tag, String message,
      {Object? error,
      StackTrace? stackTrace,
      Map<String, Object?> context = const {}}) {
    _log('ERROR', tag, message,
        context: context, sentryLevel: SentryLevel.error);
    if (error != null) {
      Sentry.captureException(error, stackTrace: stackTrace);
    }
  }

  static void _log(
    String level,
    String tag,
    String message, {
    Map<String, Object?> context = const {},
    SentryLevel sentryLevel = SentryLevel.info,
  }) {
    final text = '[$level][$tag] $message';
    if (kDebugMode) {
      debugPrint(context.isEmpty ? text : '$text | $context');
    }
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'app.$tag',
        message: message,
        level: sentryLevel,
        data: context,
      ),
    );
  }
}
