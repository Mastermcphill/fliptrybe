import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class UIFeedback {
  UIFeedback._();

  static DateTime? _lastShownAt;
  static String? _lastMessage;
  static const Duration _dedupeWindow = Duration(milliseconds: 900);

  static void showErrorSnack(BuildContext context, String message) {
    _showSnack(
      context,
      message,
      isError: true,
    );
  }

  static void showSuccessSnack(BuildContext context, String message) {
    _showSnack(
      context,
      message,
      isError: false,
    );
  }

  static void _showSnack(
    BuildContext context,
    String message, {
    required bool isError,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    if (_lastMessage == text &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < _dedupeWindow) {
      return;
    }
    _lastMessage = text;
    _lastShownAt = now;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final scheme = Theme.of(context).colorScheme;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor:
              isError ? scheme.errorContainer : scheme.secondaryContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  static String mapDioErrorToMessage(dynamic err) {
    if (err is DioException) {
      if (err.type == DioExceptionType.connectionTimeout ||
          err.type == DioExceptionType.receiveTimeout ||
          err.type == DioExceptionType.sendTimeout ||
          err.type == DioExceptionType.connectionError) {
        return 'Network timeout, try again.';
      }
      final status = err.response?.statusCode ?? 0;
      if (status == 401) return 'Session expired, please sign in again.';
      if (status >= 500) return 'Server hiccup, try again.';
      final data = err.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
    }
    return 'Something went wrong. Please try again.';
  }

  static bool shouldForceLogoutOn401(dynamic err) {
    return err is DioException && (err.response?.statusCode == 401);
  }
}
