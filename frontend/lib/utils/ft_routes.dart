import 'package:flutter/material.dart';

class FTPageRoute {
  const FTPageRoute._();

  static Route<T> fade<T>({
    required Widget child,
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) {
    return PageRouteBuilder<T>(
      transitionDuration: duration,
      reverseTransitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, widget) {
        final curved = CurvedAnimation(parent: animation, curve: curve);
        return FadeTransition(opacity: curved, child: widget);
      },
    );
  }

  static Route<T> slideUp<T>({
    required Widget child,
    Duration duration = const Duration(milliseconds: 240),
    Curve curve = Curves.easeOutCubic,
  }) {
    return PageRouteBuilder<T>(
      transitionDuration: duration,
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, widget) {
        final curved = CurvedAnimation(parent: animation, curve: curve);
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

  static Route<T> page<T>({
    required Widget child,
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) {
    return FTPageRoute.fade(
      child: child,
      duration: duration,
      curve: curve,
    );
  }

  static Route<T> slideUp<T>({
    required Widget child,
    Duration duration = const Duration(milliseconds: 240),
    Curve curve = Curves.easeOutCubic,
  }) {
    return FTPageRoute.slideUp(
      child: child,
      duration: duration,
      curve: curve,
    );
  }
}
