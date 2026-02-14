import 'package:flutter/material.dart';

import '../ui/components/ft_components.dart';
import '../utils/app_crash_state.dart';

class AppCrashOverlay extends StatelessWidget {
  const AppCrashOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CrashReport?>(
      valueListenable: AppCrashState.instance.currentCrash,
      builder: (context, crash, _) {
        if (crash == null) return child;
        return FTScaffold(
          title: 'Something went wrong',
          child: FTEmptyState(
            icon: Icons.error_outline,
            title: 'Unexpected error',
            subtitle:
                'We hit an issue and recovered the app safely. You can restart now.',
            primaryCtaText: 'Restart app',
            onPrimaryCta: () {
              AppCrashState.instance.clear();
            },
          ),
        );
      },
    );
  }
}
