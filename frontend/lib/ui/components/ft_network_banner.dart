import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../design/ft_tokens.dart';

class FTNetworkBanner extends StatefulWidget {
  const FTNetworkBanner({super.key});

  @override
  State<FTNetworkBanner> createState() => _FTNetworkBannerState();
}

class _FTNetworkBannerState extends State<FTNetworkBanner> {
  bool _visible = false;
  bool _online = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _online = ApiClient.instance.networkOnline.value;
    _visible = !_online;
    ApiClient.instance.networkOnline.addListener(_onNetworkChanged);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    ApiClient.instance.networkOnline.removeListener(_onNetworkChanged);
    super.dispose();
  }

  void _onNetworkChanged() {
    final nextOnline = ApiClient.instance.networkOnline.value;
    if (!mounted) return;
    if (!nextOnline) {
      _hideTimer?.cancel();
      setState(() {
        _online = false;
        _visible = true;
      });
      return;
    }

    // Show brief "back online" confirmation then hide.
    _hideTimer?.cancel();
    setState(() {
      _online = true;
      _visible = true;
    });
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        _online ? scheme.primaryContainer : scheme.errorContainer;
    final foreground =
        _online ? scheme.onPrimaryContainer : scheme.onErrorContainer;
    final message = _online ? 'Back online' : "You're offline";

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: !_visible
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey<bool>(_online),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: FTDesignTokens.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: FTDesignTokens.sm,
                vertical: FTDesignTokens.xs,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: FTDesignTokens.roundedSm,
              ),
              child: Row(
                children: [
                  Icon(
                    _online ? Icons.wifi : Icons.wifi_off,
                    size: 16,
                    color: foreground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
