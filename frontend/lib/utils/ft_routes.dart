import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

import '../ui/foundation/tokens/ft_motion.dart';

class FTPageRoute {
  const FTPageRoute._();

  static Route<T> fade<T>({
    required Widget child,
    Duration duration = FTMotion.emphasized,
    Curve curve = FTMotion.easeOut,
  }) {
    return PageRouteBuilder<T>(
      transitionDuration: duration,
      reverseTransitionDuration: FTMotion.quick,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, widget) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: curve,
          reverseCurve: FTMotion.easeIn,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: widget,
          ),
        );
      },
    );
  }

  static Route<T> slideUp<T>({
    required Widget child,
    Duration duration = FTMotion.emphasized,
    Curve curve = FTMotion.easeOut,
  }) {
    return PageRouteBuilder<T>(
      transitionDuration: duration,
      reverseTransitionDuration: FTMotion.quick,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, widget) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: curve,
          reverseCurve: FTMotion.easeIn,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: widget,
          ),
        );
      },
    );
  }
}

/// Backward-compatible alias used across existing screens.
class FTRoutes {
  const FTRoutes._();

  static bool get _useNativeIosTransition =>
      defaultTargetPlatform == TargetPlatform.iOS;

  static Route<T> page<T>({
    required Widget child,
    Duration duration = FTMotion.emphasized,
    Curve curve = FTMotion.easeOut,
  }) {
    if (_useNativeIosTransition) {
      return CupertinoPageRoute<T>(builder: (_) => child);
    }
    return FTPageRoute.fade(
      child: child,
      duration: duration,
      curve: curve,
    );
  }

  static Route<T> slideUp<T>({
    required Widget child,
    Duration duration = FTMotion.emphasized,
    Curve curve = FTMotion.easeOut,
  }) {
    if (_useNativeIosTransition) {
      return CupertinoPageRoute<T>(builder: (_) => child);
    }
    return FTPageRoute.slideUp(
      child: child,
      duration: duration,
      curve: curve,
    );
  }
}
