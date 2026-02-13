import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppExitBackController {
  AppExitBackController({bool? forceAndroid}) : _forceAndroid = forceAndroid;

  final bool? _forceAndroid;
  DateTime? _lastBackPress;
  bool _dialogOpen = false;

  bool get _isAndroid =>
      _forceAndroid ?? defaultTargetPlatform == TargetPlatform.android;

  Future<void> handleBackPress(BuildContext context) async {
    if (!_isAndroid) {
      final navigator = Navigator.maybeOf(context);
      if (navigator != null && await navigator.maybePop()) {
        return;
      }
      await SystemNavigator.pop();
      return;
    }

    final now = DateTime.now();
    final last = _lastBackPress;
    final withinWindow =
        last != null && now.difference(last) <= const Duration(seconds: 2);

    if (!withinWindow) {
      _lastBackPress = now;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Press back again to exit')),
      );
      return;
    }

    if (_dialogOpen) return;
    _dialogOpen = true;
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit app?'),
        content: const Text('Are you sure you want to close FlipTrybe?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (shouldExit == true) {
      await SystemNavigator.pop();
    } else {
      _lastBackPress = DateTime.now();
    }
  }
}

class AppExitGuard extends StatefulWidget {
  const AppExitGuard({super.key, required this.child});

  final Widget child;

  @override
  State<AppExitGuard> createState() => _AppExitGuardState();
}

class _AppExitGuardState extends State<AppExitGuard> {
  final AppExitBackController _controller = AppExitBackController();
  bool _handlingBack = false;

  Future<void> _onBackPressed() async {
    if (_handlingBack) return;
    _handlingBack = true;
    try {
      final navigator = Navigator.maybeOf(context);
      if (navigator != null && await navigator.maybePop()) {
        return;
      }
      if (!mounted) return;
      await _controller.handleBackPress(context);
    } finally {
      _handlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_onBackPressed());
      },
      child: widget.child,
    );
  }
}
