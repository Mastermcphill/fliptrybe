import 'package:flutter/foundation.dart';

class AppCrashState {
  AppCrashState._();

  static final AppCrashState instance = AppCrashState._();

  final ValueNotifier<CrashReport?> currentCrash =
      ValueNotifier<CrashReport?>(null);

  void capture(Object error, StackTrace? stackTrace) {
    currentCrash.value = CrashReport(error, stackTrace);
  }

  void clear() {
    currentCrash.value = null;
  }
}

class CrashReport {
  const CrashReport(this.error, this.stackTrace);

  final Object error;
  final StackTrace? stackTrace;
}
