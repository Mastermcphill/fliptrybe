import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/ng_states.dart';
import '../services/analytics_hooks.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';
import '../shells/buyer_shell.dart';
import '../shells/driver_shell.dart';
import '../shells/inspector_shell.dart';
import '../shells/merchant_shell.dart';
import '../ui/components/ft_components.dart';
import '../utils/ft_routes.dart';
import '../utils/ui_feedback.dart';
import '../widgets/app_exit_guard.dart';
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _referralCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _reasonFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  String _role = 'user';
  String _selectedState = 'Lagos';
  bool _loading = false;

  final _roles = const [
    {'label': 'User', 'value': 'user'},
    {'label': 'Merchant', 'value': 'merchant'},
    {'label': 'Driver', 'value': 'driver'},
  ];

  String _roleToBackend(String role) {
    switch (role.toLowerCase()) {
      case 'merchant':
        return 'merchant';
      case 'driver':
        return 'driver';
      default:
        return 'buyer';
    }
  }

  Widget _screenForRole(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'driver') return const AppExitGuard(child: DriverShell());
    if (r == 'merchant') return const AppExitGuard(child: MerchantShell());
    if (r == 'inspector') return const AppExitGuard(child: InspectorShell());
    return const AppExitGuard(child: BuyerShell());
  }

  void _toast(String msg) {
    if (!mounted) return;
    UIFeedback.showErrorSnack(context, msg);
  }

  void _log(String message) {
    debugPrint('[SignUpScreen] $message');
  }

  Future<void> _signup() async {
    _log('tap received');
    if (_loading) return;

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'\s+'), '').trim();
    final reason = _reasonCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (name.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        password.isEmpty ||
        confirm.isEmpty) {
      _toast('All fields are required.');
      return;
    }
    if (password != confirm) {
      _toast('Passwords do not match.');
      return;
    }
    if (_role == 'merchant' && reason.isEmpty) {
      _toast('Please tell us why you want a merchant account.');
      return;
    }

    setState(() => _loading = true);
    _log('request started');

    try {
      final backendRole = _roleToBackend(_role);
      String path;
      Map<String, dynamic> payload;

      if (backendRole == 'merchant') {
        path = '/auth/register/merchant';
        payload = {
          'owner_name': name,
          'email': email,
          'password': password,
          'business_name': '$name Store',
          'phone': phone,
          'state': _selectedState,
          'city': _selectedState == 'Federal Capital Territory'
              ? 'Abuja'
              : _selectedState,
          'category': 'general',
          'reason': reason,
          'referral_code': _referralCtrl.text.trim(),
        };
      } else if (backendRole == 'driver') {
        path = '/auth/register/driver';
        payload = {
          'name': name,
          'email': email,
          'password': password,
          'phone': phone,
          'state': _selectedState,
          'city': _selectedState == 'Federal Capital Territory'
              ? 'Abuja'
              : _selectedState,
          'vehicle_type': 'bike',
          'plate_number': 'DEMO-001',
          'referral_code': _referralCtrl.text.trim(),
        };
      } else {
        path = '/auth/register/buyer';
        payload = {
          'name': name,
          'email': email,
          'password': password,
          'phone': phone,
          'referral_code': _referralCtrl.text.trim(),
        };
      }

      if (kDebugMode) {
        final keys =
            payload.keys.where((k) => k.toLowerCase() != 'password').toList();
        debugPrint('Signup payload keys: $keys role=$_role path=$path');
      }

      final res =
          await ApiClient.instance.postJson(ApiConfig.api(path), payload);
      if (res is! Map) {
        _log('request failed: non-map response');
        _toast('Signup failed.');
        return;
      }

      final token = (res['token'] ?? res['access_token'])?.toString() ?? '';
      if (token.isEmpty) {
        _log('request failed: empty token');
        _toast(res['message']?.toString() ?? 'Signup failed.');
        return;
      }

      await ApiService.persistAuthPayload(res.map((k, v) => MapEntry('$k', v)));
      await AnalyticsHooks.instance.signupSuccess(role: backendRole);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        FTRoutes.page(child: _screenForRole(backendRole)),
      );
      _log('response received');
    } catch (e) {
      _log('request failed: $e');
      _toast(UIFeedback.mapDioErrorToMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
      _log('loading reset');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _reasonCtrl.dispose();
    _referralCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _reasonFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Create Account',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTDropDownField<String>(
              initialValue: _role,
              labelText: 'Role',
              items: _roles
                  .map(
                    (r) => DropdownMenuItem<String>(
                      value: r['value'],
                      child: Text(r['label'] ?? ''),
                    ),
                  )
                  .toList(),
              onChanged:
                  _loading ? null : (v) => setState(() => _role = v ?? 'user'),
            ),
            const SizedBox(height: 14),
            FTTextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              nextFocusNode: _emailFocus,
              labelText: 'Full Name',
              prefixIcon: Icons.person_outline,
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            FTTextField(
              controller: _emailCtrl,
              focusNode: _emailFocus,
              nextFocusNode: _phoneFocus,
              keyboardType: TextInputType.emailAddress,
              labelText: 'Email',
              prefixIcon: Icons.mail_outline,
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            FTPhoneField(
              controller: _phoneCtrl,
              focusNode: _phoneFocus,
              nextFocusNode:
                  _role == 'merchant' ? _reasonFocus : _passwordFocus,
              labelText: 'Phone Number',
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            if (_role == 'merchant') ...[
              FTTextField(
                controller: _reasonCtrl,
                focusNode: _reasonFocus,
                nextFocusNode: _passwordFocus,
                labelText: 'Reason for merchant account',
                hintText: 'Tell us why you want to sell on FlipTrybe',
                enabled: !_loading,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
            ],
            if (_role == 'merchant' || _role == 'driver') ...[
              FTDropDownField<String>(
                initialValue: _selectedState,
                labelText: 'State',
                items: nigeriaStates
                    .map(
                      (s) => DropdownMenuItem<String>(
                        value: s,
                        child: Text(displayState(s)),
                      ),
                    )
                    .toList(),
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _selectedState = v ?? 'Lagos'),
              ),
              const SizedBox(height: 12),
            ],
            FTTextField(
              controller: _referralCtrl,
              labelText: 'Referral Code (optional)',
              prefixIcon: Icons.card_giftcard_outlined,
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            FTPasswordField(
              controller: _passwordCtrl,
              focusNode: _passwordFocus,
              nextFocusNode: _confirmFocus,
              labelText: 'Password',
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            FTPasswordField(
              controller: _confirmCtrl,
              focusNode: _confirmFocus,
              textInputAction: TextInputAction.done,
              labelText: 'Confirm Password',
              enabled: !_loading,
              onSubmitted: (_) => _signup(),
            ),
            const SizedBox(height: 18),
            FTAsyncButton(
              label: 'Create Account',
              variant: FTButtonVariant.primary,
              externalLoading: _loading,
              onPressed: _loading ? null : _signup,
            ),
            const SizedBox(height: 14),
            FTButton(
              label: 'Already have an account? Login',
              variant: FTButtonVariant.ghost,
              onPressed: _loading
                  ? null
                  : () {
                      Navigator.of(context).pushReplacement(
                        FTRoutes.slideUp(child: const LoginScreen()),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }
}
