import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/token_storage.dart';
import 'pending_approval_screen.dart';
import 'role_signup_screen.dart';
import 'forgot_password_screen.dart';
import '../shells/admin_shell.dart';
import '../shells/buyer_shell.dart';
import '../shells/driver_shell.dart';
import '../shells/merchant_shell.dart';
import '../shells/inspector_shell.dart';
import '../utils/auth_navigation.dart';
import '../widgets/app_exit_guard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.loginAction,
    this.meAction,
  });

  final Future<Map<String, dynamic>> Function(String email, String password)?
      loginAction;
  final Future<Map<String, dynamic>?> Function()? meAction;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _devTokenController = TextEditingController();

  bool _isLoading = false;

  Widget _screenForRole(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'admin') return const AppExitGuard(child: AdminShell());
    if (r == 'driver') return const AppExitGuard(child: DriverShell());
    if (r == 'merchant') return const AppExitGuard(child: MerchantShell());
    if (r == 'inspector') return const AppExitGuard(child: InspectorShell());
    return const AppExitGuard(child: BuyerShell());
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _log(String message) {
    debugPrint('[LoginScreen] $message');
  }

  Future<void> _handleLogin() async {
    _log('tap received');
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _toast('Email and password are required.');
      return;
    }

    setState(() => _isLoading = true);
    _log('request started');

    try {
      final res = widget.loginAction != null
          ? await widget.loginAction!(email, password)
          : await ApiService.login(email: email, password: password);
      _log('response received');
      final token = (res['token'] ?? res['access_token'])?.toString() ?? '';
      if (token.isEmpty) {
        _toast(res['message']?.toString() ?? 'Login failed.');
        return;
      }

      String roleForNav = 'buyer';
      String roleStatus = 'approved';
      final profile =
          widget.meAction != null ? await widget.meAction!() : await _auth.me();
      roleForNav = (profile?['role'] ?? 'buyer').toString();
      roleStatus = (profile?['role_status'] ?? 'approved').toString();

      if (!mounted) return;
      if (roleStatus.toLowerCase() == 'pending') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => PendingApprovalScreen(role: roleForNav)),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => _screenForRole(roleForNav)),
        );
      }
    } catch (e) {
      _log('request failed: $e');
      _toast('Login error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _log('loading reset');
    }
  }

  Future<void> _handleDevTokenLogin() async {
    if (!kDebugMode) return;
    if (_isLoading) return;
    final token = _devTokenController.text.trim();
    if (token.isEmpty) {
      _toast('Paste a token first.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await TokenStorage().saveToken(token);
      ApiService.setToken(token);

      final profile = await _auth.me();
      if (!mounted) return;

      if (profile == null) {
        _toast('Token invalid or expired.');
        await logoutToLanding(context);
        if (!mounted) return;
        return;
      }

      final roleForNav = (profile['role'] ?? 'buyer').toString();
      final roleStatus = (profile['role_status'] ?? 'approved').toString();

      if (!mounted) return;
      if (roleStatus.toLowerCase() == 'pending') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => PendingApprovalScreen(role: roleForNav)),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => _screenForRole(roleForNav)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _devTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                child: Text(_isLoading ? 'Please wait...' : 'Login'),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen()),
                      );
                    },
              child: const Text('Forgot Password?'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const RoleSignupScreen()),
                      );
                    },
              child: const Text('Create Account'),
            ),
            const SizedBox(height: 16),
            if (kDebugMode) ...[
              const Divider(),
              const SizedBox(height: 12),
              TextField(
                controller: _devTokenController,
                decoration: const InputDecoration(
                  labelText: 'Dev token',
                  hintText: 'Paste Bearer token',
                  border: OutlineInputBorder(),
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _handleDevTokenLogin,
                  child: const Text('Use Dev Token'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
