import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/token_storage.dart';
import '../ui/components/ft_components.dart';
import '../utils/ft_routes.dart';
import '../utils/ui_feedback.dart';
import '../widgets/app_exit_guard.dart';
import '../shells/admin_shell.dart';
import '../shells/buyer_shell.dart';
import '../shells/driver_shell.dart';
import '../shells/inspector_shell.dart';
import '../shells/merchant_shell.dart';
import 'forgot_password_screen.dart';
import 'pending_approval_screen.dart';
import 'role_signup_screen.dart';

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
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isLoading = false;
  String? _emailError;
  String? _passwordError;

  Widget _screenForRole(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'admin') return const AppExitGuard(child: AdminShell());
    if (r == 'driver') return const AppExitGuard(child: DriverShell());
    if (r == 'merchant') return const AppExitGuard(child: MerchantShell());
    if (r == 'inspector') return const AppExitGuard(child: InspectorShell());
    return const AppExitGuard(child: BuyerShell());
  }

  String? _validateEmail(String email) {
    final v = email.trim();
    if (v.isEmpty) return 'Email is required';
    if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String password) {
    if (password.trim().isEmpty) return 'Password is required';
    return null;
  }

  bool _validateFields() {
    final emailError = _validateEmail(_emailController.text);
    final passwordError = _validatePassword(_passwordController.text);
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });
    if (emailError != null || passwordError != null) {
      UIFeedback.showErrorSnack(
          context, 'Enter a valid email and password to continue.');
      return false;
    }
    return true;
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_validateFields()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);

    try {
      final res = widget.loginAction != null
          ? await widget.loginAction!(email, password)
          : await ApiService.login(email: email, password: password);
      final token = (res['token'] ?? res['access_token'])?.toString() ?? '';
      if (token.isEmpty) {
        if (!mounted) return;
        UIFeedback.showErrorSnack(
            context, res['message']?.toString() ?? 'Login failed.');
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
          FTRoutes.page(
            child: PendingApprovalScreen(role: roleForNav),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          FTRoutes.page(
            child: _screenForRole(roleForNav),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleDevTokenLogin() async {
    if (!kDebugMode || _isLoading) return;
    final token = _devTokenController.text.trim();
    if (token.isEmpty) {
      UIFeedback.showErrorSnack(context, 'Paste a token first.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await TokenStorage().saveToken(token);
      ApiService.setToken(token);

      final profile = await _auth.me();
      if (!mounted) return;

      if (profile == null) {
        UIFeedback.showErrorSnack(context, 'Token invalid or expired.');
        return;
      }

      final roleForNav = (profile['role'] ?? 'buyer').toString();
      final roleStatus = (profile['role_status'] ?? 'approved').toString();

      if (roleStatus.toLowerCase() == 'pending') {
        Navigator.of(context).pushReplacement(
          FTRoutes.page(child: PendingApprovalScreen(role: roleForNav)),
        );
      } else {
        Navigator.of(context).pushReplacement(
          FTRoutes.page(child: _screenForRole(roleForNav)),
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
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Login',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTTextField(
              controller: _emailController,
              focusNode: _emailFocus,
              nextFocusNode: _passwordFocus,
              keyboardType: TextInputType.emailAddress,
              labelText: 'Email',
              hintText: 'name@email.com',
              prefixIcon: Icons.mail_outline,
              errorText: _emailError,
              enabled: !_isLoading,
              onChanged: (_) {
                if (_emailError != null) {
                  setState(() => _emailError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            FTPasswordField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              textInputAction: TextInputAction.done,
              labelText: 'Password',
              errorText: _passwordError,
              enabled: !_isLoading,
              onSubmitted: (_) => _handleLogin(),
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() => _passwordError = null);
                }
              },
            ),
            const SizedBox(height: 18),
            Semantics(
              label: 'Login action',
              button: true,
              child: FTPrimaryButton(
                label: 'Login',
                loading: _isLoading,
                onPressed: _isLoading ? null : _handleLogin,
              ),
            ),
            const SizedBox(height: 12),
            FTButton(
              label: 'Forgot Password?',
              variant: FTButtonVariant.ghost,
              onPressed: _isLoading
                  ? null
                  : () {
                      Navigator.of(context).push(
                        FTRoutes.page(child: const ForgotPasswordScreen()),
                      );
                    },
            ),
            const SizedBox(height: 8),
            FTButton(
              label: 'Create Account',
              variant: FTButtonVariant.secondary,
              onPressed: _isLoading
                  ? null
                  : () {
                      Navigator.of(context).pushReplacement(
                        FTRoutes.page(child: const RoleSignupScreen()),
                      );
                    },
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              FTTextField(
                controller: _devTokenController,
                labelText: 'Dev token',
                hintText: 'Paste Bearer token',
                prefixIcon: Icons.key_outlined,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 10),
              FTButton(
                label: 'Use Dev Token',
                variant: FTButtonVariant.ghost,
                onPressed: _isLoading ? null : _handleDevTokenLogin,
                expand: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
