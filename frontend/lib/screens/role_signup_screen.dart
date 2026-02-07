import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';
import '../services/token_storage.dart';
import 'pending_approval_screen.dart';

class RoleSignupScreen extends StatefulWidget {
  const RoleSignupScreen({super.key});

  @override
  State<RoleSignupScreen> createState() => _RoleSignupScreenState();
}

class _RoleSignupScreenState extends State<RoleSignupScreen> {
  String _role = "buyer";
  bool _loading = false;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  // shared
  final _phone = TextEditingController();
  final _state = TextEditingController(text: "Lagos");
  final _city = TextEditingController(text: "Lagos");

  // merchant
  final _business = TextEditingController();
  final _category = TextEditingController(text: "general");
  final _reason = TextEditingController();

  // driver
  final _vehicle = TextEditingController(text: "bike");
  final _plate = TextEditingController(text: "LAG-123");

  // inspector
  final _region = TextEditingController();
  final _inspectorReason = TextEditingController();

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _signup() async {
    setState(() => _loading = true);

    try {
      final name = _name.text.trim();
      final email = _email.text.trim();
      final password = _password.text.trim();
      final phone = _phone.text.trim();

      if (name.isEmpty) {
        _toast("Full name is required");
        return;
      }
      if (!email.contains("@")) {
        _toast("A valid email is required");
        return;
      }
      if (password.length < 4) {
        _toast("Password must be at least 4 characters");
        return;
      }
      if (phone.isEmpty) {
        _toast("Phone is required");
        return;
      }

      String path = "/auth/register/buyer";
      Map<String, dynamic> payload = {
        "name": name,
        "email": email,
        "password": password,
        "phone": phone,
      };

      if (_role == "buyer") {
        // “Buy & Sell” = buyer role in backend
        path = "/auth/register/buyer";
      } else if (_role == "merchant") {
        if (_business.text.trim().isEmpty) {
          _toast("Business name is required");
          return;
        }
        if (_reason.text.trim().isEmpty) {
          _toast("Tell us why you want a merchant account");
          return;
        }
        path = "/auth/register/merchant";
        payload = {
          "owner_name": name,
          "email": email,
          "password": password,
          "phone": phone,
          "business_name": _business.text.trim(),
          "state": _state.text.trim(),
          "city": _city.text.trim(),
          "category": _category.text.trim(),
          "reason": _reason.text.trim(),
        };
      } else if (_role == "driver") {
        path = "/auth/register/driver";
        payload = {
          "name": name,
          "email": email,
          "password": password,
          "phone": phone,
          "state": _state.text.trim(),
          "city": _city.text.trim(),
          "vehicle_type": _vehicle.text.trim(),
          "plate_number": _plate.text.trim(),
        };
      } else if (_role == "inspector") {
        if (_inspectorReason.text.trim().isEmpty) {
          _toast("Tell us why you want to be an inspector");
          return;
        }
        path = "/auth/register/inspector";
        payload = {
          "name": name,
          "email": email,
          "password": password,
          "phone": phone,
          "state": _state.text.trim(),
          "city": _city.text.trim(),
          "region": _region.text.trim(),
          "reason": _inspectorReason.text.trim(),
        };
      }

      if (kDebugMode) {
        final keys = payload.keys.where((k) => k.toLowerCase() != "password").toList();
        debugPrint("Signup payload keys: $keys role=$_role path=$path");
      }

      final res = await ApiClient.instance.postJson(ApiConfig.api(path), payload);

      if (res is Map && res["token"] != null) {
        final token = res["token"].toString();
        ApiService.setToken(token);
        ApiClient.instance.setAuthToken(token);
        await TokenStorage().saveToken(token);
        final status = (res["status"] ?? "").toString().toLowerCase();
        if (!mounted) return;
        if (status == "pending" || status == "pending_approval") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => PendingApprovalScreen(role: _role)),
          );
        } else {
          _toast("Account created");
          Navigator.pop(context, true);
        }
      } else if (res is Map && res["message"] != null) {
        _toast(res["message"].toString());
      } else {
        _toast("Signup failed");
      }
    } catch (e) {
      _toast("Signup error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _roleCard({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _role == value;
    return InkWell(
      onTap: _loading ? null : () => setState(() => _role = value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0B1220) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Colors.black : const Color(0xFFE5E7EB)),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? Colors.white.withOpacity(0.12) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: selected ? Colors.white : const Color(0xFF0F172A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      height: 1.25,
                      color: selected ? Colors.white.withOpacity(0.9) : const Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _state.dispose();
    _city.dispose();
    _business.dispose();
    _category.dispose();
    _reason.dispose();
    _vehicle.dispose();
    _plate.dispose();
    _region.dispose();
    _inspectorReason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Choose your path")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Secure deals. Verified delivery. Peace of mind.",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              "Pick how you want to use FlipTrybe. You can upgrade roles later, but this helps us set you up right from day one.",
              style: TextStyle(color: Colors.black.withOpacity(0.65), height: 1.3),
            ),
            const SizedBox(height: 14),

            _roleCard(
              value: "buyer",
              title: "Users (Buy & Sell)",
              subtitle: "Buy and sell items safely with escrow and delivery confirmation.",
              icon: Icons.shopping_bag_rounded,
            ),
            const SizedBox(height: 10),
            _roleCard(
              value: "merchant",
              title: "Merchants",
              subtitle: "List items, manage orders, and grow followers.",
              icon: Icons.storefront_rounded,
            ),
            const SizedBox(height: 10),
            _roleCard(
              value: "driver",
              title: "Drivers",
              subtitle: "Deliver orders and earn. Access driver jobs based on locality.",
              icon: Icons.delivery_dining_rounded,
            ),
            const SizedBox(height: 10),
            _roleCard(
              value: "inspector",
              title: "Inspectors",
              subtitle: "Verify items and approve inspection tasks.",
              icon: Icons.verified_user_rounded,
            ),

            const Divider(height: 28),

            _field(_name, "Full name"),
            _field(_email, "Email", keyboard: TextInputType.emailAddress),
            _field(_password, "Password"),
            _field(_phone, "Phone", keyboard: TextInputType.phone),

            if (_role != "buyer") ...[
              const SizedBox(height: 6),
              _field(_state, "State"),
              _field(_city, "City"),
            ],

            if (_role == "merchant") ...[
              const Divider(height: 28),
              _field(_business, "Business name"),
              _field(_category, "Category"),
              _field(_reason, "Why do you want a merchant account?"),
            ],

            if (_role == "driver") ...[
              const Divider(height: 28),
              _field(_vehicle, "Vehicle type"),
              _field(_plate, "Plate number"),
            ],

            if (_role == "inspector") ...[
              const Divider(height: 28),
              _field(_region, "Region (optional)"),
              _field(_inspectorReason, "Why do you want to be an inspector?"),
            ],

            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _signup,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.lock_rounded),
                label: Text(_loading ? "Creating..." : "Create account"),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _role == "buyer"
                  ? "Tip: You can start buying/selling instantly."
                  : "Note: ${_role.toUpperCase()} activation is reviewed for safety. You'll still have access to Buy & Sell while we verify you.",
              style: TextStyle(color: Colors.black.withOpacity(0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
