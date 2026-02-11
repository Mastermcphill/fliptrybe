import 'package:flutter/material.dart';

import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/role_signup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/admin_hub_screen.dart';
import 'screens/pending_approval_screen.dart';
import 'shells/merchant_shell.dart';
import 'shells/driver_shell.dart';
import 'shells/inspector_shell.dart';
import 'services/api_service.dart';
import 'services/api_config.dart';
import 'services/token_storage.dart';

void main() {
  ApiConfig.logStartup();
  runApp(const FlipTrybeApp());
}

class FlipTrybeApp extends StatelessWidget {
  const FlipTrybeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlipTrybe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: const StartupScreen(),
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _isLoading = true;
  bool _loggedIn = false;
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
        if (!mounted) return;
        setState(() {
          _loggedIn = false;
          _isLoading = false;
        });
        return;
      }

      ApiService.setToken(token);
      final res = await ApiService.getProfileResponse();

      if (res.statusCode == 401) {
        await TokenStorage().clear();
        ApiService.setToken(null);
        if (!mounted) return;
        setState(() {
          _loggedIn = false;
          _isLoading = false;
        });
        return;
      }

      final user = _unwrapUser(res.data);

      if (!mounted) return;
      setState(() {
        _loggedIn = user != null;
        _isLoading = false;
      });
      if (user != null) {
        _navigateToRoleHome(
          (user['role'] ?? 'buyer').toString(),
          roleStatus: (user['role_status'] ?? 'approved').toString(),
        );
      }
    } catch (e) {
      debugPrint("Session check failed: $e");
      if (!mounted) return;
      setState(() {
        _loggedIn = false;
        _isLoading = false;
      });
    } finally {
      _hasCheckedSession = true;
      _isCheckingSession = false;
    }
  }

  Widget _screenForRole(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'admin') return const AdminHubScreen();
    if (r == 'driver') return const DriverShell();
    if (r == 'merchant') return const MerchantShell();
    if (r == 'inspector') return const InspectorShell();
    return const HomeScreen();
  }

  void _navigateToRoleHome(String role, {String? roleStatus}) {
    if (_hasNavigated) return;
    _hasNavigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final status = (roleStatus ?? 'approved').toLowerCase();
      if (status == 'pending') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => PendingApprovalScreen(role: role)),
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
    );
  }
}
