import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'dart:async';
import 'dart:ui';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/role_signup_screen.dart';
import 'screens/pending_approval_screen.dart';
import 'screens/investor_metrics_screen.dart';
import 'shells/admin_shell.dart';
import 'shells/buyer_shell.dart';
import 'shells/merchant_shell.dart';
import 'shells/driver_shell.dart';
import 'shells/inspector_shell.dart';
import 'shells/public_browse_shell.dart';
import 'public_site/public_marketing_site.dart';
import 'services/api_client.dart';
import 'services/api_service.dart';
import 'services/api_config.dart';
import 'utils/app_crash_state.dart';
import 'utils/auth_navigation.dart';
import 'utils/ft_logger.dart';
import 'widgets/app_crash_overlay.dart';
import 'widgets/app_exit_guard.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/theme_controller.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ApiConfig.logStartup();
  const sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  const gitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');
  if (sentryDsn.trim().isEmpty) {
    _installGlobalErrorHandlers(sentryEnabled: false);
    runZonedGuarded(
      () => runApp(const FlipTrybeApp()),
      (error, stackTrace) {
        AppCrashState.instance.capture(error, stackTrace);
        FTLogger.logError(
          'zone',
          'Unhandled zone error',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = sentryDsn;
      options.environment = const String.fromEnvironment('SENTRY_ENVIRONMENT',
          defaultValue: 'dev');
      options.release = 'fliptrybe@${ApiConfig.appVersion}+$gitSha';
      options.tracesSampleRate = double.tryParse(const String.fromEnvironment(
              'SENTRY_TRACES_SAMPLE_RATE',
              defaultValue: '0.0')) ??
          0.0;
      options.attachStacktrace = true;
      options.sendDefaultPii = false;
    },
    appRunner: () {
      _installGlobalErrorHandlers(sentryEnabled: true);
      runZonedGuarded(
        () => runApp(const FlipTrybeApp()),
        (error, stackTrace) {
          AppCrashState.instance.capture(error, stackTrace);
          FTLogger.logError(
            'zone',
            'Unhandled zone error',
            error: error,
            stackTrace: stackTrace,
          );
          Sentry.captureException(error, stackTrace: stackTrace);
        },
      );
    },
  );
}

void _installGlobalErrorHandlers({required bool sentryEnabled}) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppCrashState.instance.capture(details.exception, details.stack);
    FTLogger.logError(
      'flutter_error',
      details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
    );
    if (sentryEnabled) {
      Sentry.captureException(
        details.exception,
        stackTrace: details.stack,
      );
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppCrashState.instance.capture(error, stack);
    FTLogger.logError(
      'platform_error',
      'Unhandled platform error',
      error: error,
      stackTrace: stack,
    );
    if (sentryEnabled) {
      Sentry.captureException(error, stackTrace: stack);
      return true;
    }
    return false;
  };
}

class FlipTrybeApp extends StatefulWidget {
  const FlipTrybeApp({super.key});

  @override
  State<FlipTrybeApp> createState() => _FlipTrybeAppState();
}

class _FlipTrybeAppState extends State<FlipTrybeApp>
    with WidgetsBindingObserver {
  late final ThemeController _themeController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeController = ThemeController();
    _themeController.load();
    ApiClient.instance.configureGlobalHandlers(
      onUnauthorized: () async {
        final context = appNavigatorKey.currentContext;
        if (context == null) return;
        await logoutToLanding(context);
      },
      onErrorMessage: (message) {
        final messenger = appScaffoldMessengerKey.currentState;
        if (messenger == null) return;
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ApiService.revalidateSessionOnResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeControllerProvider(
      controller: _themeController,
      child: AnimatedBuilder(
        animation: _themeController,
        builder: (context, _) => MaterialApp(
          title: 'FlipTrybe',
          debugShowCheckedModeBanner: false,
          navigatorKey: appNavigatorKey,
          scaffoldMessengerKey: appScaffoldMessengerKey,
          navigatorObservers: [SentryNavigatorObserver()],
          theme: AppTheme.light(_themeController.backgroundPalette),
          darkTheme: AppTheme.dark(_themeController.backgroundPalette),
          themeMode: _themeController.themeMode,
          builder: (context, child) {
            Widget wrapped = AppCrashOverlay(
              child: child ?? const SizedBox.shrink(),
            );
            final mediaQuery = MediaQuery.maybeOf(context);
            if (mediaQuery != null) {
              wrapped = MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: mediaQuery.textScaler.clamp(
                    minScaleFactor: 1.0,
                    maxScaleFactor: 1.3,
                  ),
                ),
                child: wrapped,
              );
            }
            if (kReleaseMode) return wrapped;
            final envTag = const String.fromEnvironment(
              'APP_ENV',
              defaultValue: 'dev',
            ).toUpperCase();
            return Stack(
              children: [
                wrapped,
                Positioned(
                  top: 8,
                  right: 8,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Text(
                          envTag,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          home: const AppExitGuard(child: StartupScreen()),
        ),
      ),
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final String _initialPath = Uri.base.path;
  bool _isCheckingSession = false;
  bool _hasCheckedSession = false;
  bool _hasNavigated = false;

  bool get _isInvestorPath => _initialPath.trim().toLowerCase() == '/investor';
  bool get _isMarketingPath =>
      PublicMarketingSite.isMarketingPath(_initialPath);

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    if (_isCheckingSession || _hasCheckedSession) return;
    _isCheckingSession = true;
    try {
      final restored = await ApiService.restoreSession();
      if (restored.authenticated && restored.user != null) {
        final user = restored.user!;
        await ApiService.syncSentryUser(user);
        if (_isInvestorPath) {
          _navigateToInvestorDashboard();
          return;
        }
        _navigateToRoleHome(
          (user['role'] ?? 'buyer').toString(),
          roleStatus: (user['role_status'] ?? 'approved').toString(),
        );
      }
    } catch (e) {
      debugPrint("Session check failed: $e");
    } finally {
      _hasCheckedSession = true;
      _isCheckingSession = false;
    }
  }

  Widget _screenForRole(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'admin') return const AppExitGuard(child: AdminShell());
    if (r == 'driver') return const AppExitGuard(child: DriverShell());
    if (r == 'merchant') return const AppExitGuard(child: MerchantShell());
    if (r == 'inspector') return const AppExitGuard(child: InspectorShell());
    return const AppExitGuard(child: BuyerShell());
  }

  void _navigateToRoleHome(String role, {String? roleStatus}) {
    if (_hasNavigated) return;
    _hasNavigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final status = (roleStatus ?? 'approved').toLowerCase();
      if (status == 'pending') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AppExitGuard(
              child: PendingApprovalScreen(role: role),
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => _screenForRole(role)),
        );
      }
    });
  }

  void _navigateToInvestorDashboard() {
    if (_hasNavigated) return;
    _hasNavigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const AppExitGuard(child: InvestorMetricsScreen()),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInvestorPath) {
      return const LoginScreen();
    }
    if (kIsWeb && _isMarketingPath) {
      return PublicMarketingSite(
        initialPath: _initialPath,
        onLogin: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        },
        onSignup: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RoleSignupScreen()),
          );
        },
      );
    }
    return LandingScreen(
      onLogin: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      },
      onSignup: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RoleSignupScreen()),
        );
      },
      onBrowseMarketplace: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PublicBrowseShell(initialIndex: 1),
          ),
        );
      },
      onBrowseShortlets: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PublicBrowseShell(initialIndex: 2),
          ),
        );
      },
    );
  }
}
