import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/role_signup_screen.dart';
import 'screens/pending_approval_screen.dart';
import 'shells/admin_shell.dart';
import 'shells/buyer_shell.dart';
import 'shells/merchant_shell.dart';
import 'shells/driver_shell.dart';
import 'shells/inspector_shell.dart';
import 'shells/public_browse_shell.dart';
import 'services/api_service.dart';
import 'services/api_config.dart';
import 'services/token_storage.dart';
import 'widgets/app_exit_guard.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ApiConfig.logStartup();
  const sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  const gitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');
  if (sentryDsn.trim().isEmpty) {
    _installGlobalErrorHandlers(sentryEnabled: false);
    runApp(const FlipTrybeApp());
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
      runApp(const FlipTrybeApp());
    },
  );
}

void _installGlobalErrorHandlers({required bool sentryEnabled}) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (sentryEnabled) {
      Sentry.captureException(
        details.exception,
        stackTrace: details.stack,
      );
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
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

class _FlipTrybeAppState extends State<FlipTrybeApp> {
  late final ThemeController _themeController;

  @override
  void initState() {
    super.initState();
    _themeController = ThemeController();
    _themeController.load();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
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
          navigatorObservers: [SentryNavigatorObserver()],
          theme: AppTheme.light(_themeController.backgroundPalette),
          darkTheme: AppTheme.dark(_themeController.backgroundPalette),
          themeMode: _themeController.themeMode,
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
  bool _isCheckingSession = false;
  bool _hasCheckedSession = false;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  bool _looksLikeUser(Map<String, dynamic> u) {
    final id = u['id'];
    final email = u['email'];
    final name = u['name'];

    final hasId = id is int || (id is String && id.trim().isNotEmpty);
    final hasEmail = email is String && email.trim().isNotEmpty;
    final hasName = name is String && name.trim().isNotEmpty;

    return hasId && (hasEmail || hasName);
  }

  Map<String, dynamic>? _unwrapUser(dynamic data) {
    if (data is Map<String, dynamic>) {
      final maybeUser = data['user'];
      if (maybeUser is Map<String, dynamic> && _looksLikeUser(maybeUser)) {
        return maybeUser;
      }
      if (_looksLikeUser(data)) {
        return data;
      }
    }
    if (data is Map) {
      final cast = data.map((k, v) => MapEntry('$k', v));
      return _unwrapUser(cast);
    }
    return null;
  }

  Future<void> _checkSession() async {
    if (_isCheckingSession || _hasCheckedSession) return;
    _isCheckingSession = true;
    try {
      final storedToken = await TokenStorage().readToken();
      final token = storedToken?.trim() ?? '';

      if (token.isEmpty) {
        ApiService.setToken(null);
        return;
      }

      ApiService.setToken(token);
      final res = await ApiService.getProfileResponse();

      if (res.statusCode == 401) {
        await TokenStorage().clear();
        ApiService.setToken(null);
        return;
      }

      final user = _unwrapUser(res.data);

      if (user != null) {
        await ApiService.syncSentryUser(user);
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

  @override
  Widget build(BuildContext context) {
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
