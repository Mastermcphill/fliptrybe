import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';
import '../services/token_storage.dart';
import 'driver_jobs_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'merchant_dashboard_screen.dart';

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
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String _role = 'user';
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
    if (r == 'driver') return const DriverJobsScreen();
    if (r == 'merchant') return const MerchantDashboardScreen();
    return const HomeScreen();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _signup() async {
    if (_loading) return;

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final reason = _reasonCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (name.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty || confirm.isEmpty) {
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
          'state': 'Lagos',
          'city': 'Lagos',
          'category': 'general',
          'reason': reason,
        };
      } else if (backendRole == 'driver') {
        path = '/auth/register/driver';
        payload = {
          'name': name,
          'email': email,
          'password': password,
          'phone': phone,
          'state': 'Lagos',
          'city': 'Lagos',
          'vehicle_type': 'bike',
          'plate_number': 'DEMO-001',
        };
      } else {
        path = '/auth/register/buyer';
        payload = {
          'name': name,
          'email': email,
          'password': password,
          'phone': phone,
        };
      }

      if (kDebugMode) {
        final keys = payload.keys.where((k) => k.toLowerCase() != 'password').toList();
        debugPrint('Signup payload keys: $keys role=$_role path=$path');
      }

      final res = await ApiClient.instance.postJson(ApiConfig.api(path), payload);
      if (res is! Map) {
        _toast('Signup failed.');
        return;
      }

      final token = (res['token'] ?? res['access_token'])?.toString() ?? '';
      if (token.isEmpty) {
        _toast(res['message']?.toString() ?? 'Signup failed.');
        return;
      }

      ApiService.setToken(token);
      ApiClient.instance.setAuthToken(token);
      await TokenStorage().saveToken(token);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => _screenForRole(backendRole)),
      );
    } catch (e) {
      _toast('Signup error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _reasonCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
              items: _roles
                  .map(
                    (r) => DropdownMenuItem(
                      value: r['value'],
                      child: Text(r['label'] ?? ''),
                    ),
                  )
                  .toList(),
              onChanged: _loading ? null : (v) => setState(() => _role = v ?? 'user'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
              ),
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            if (_role == 'merchant') ...[
              TextField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason for merchant account',
                  hintText: 'Tell us why you want to sell on FlipTrybe',
                  border: OutlineInputBorder(),
                ),
                enabled: !_loading,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                border: OutlineInputBorder(),
              ),
              enabled: !_loading,
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _signup,
                child: Text(_loading ? 'Creating...' : 'Create Account'),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
              child: const Text('Already have an account? Login'),
            ),
          ],
        ),
      ),
    );
  }
}
