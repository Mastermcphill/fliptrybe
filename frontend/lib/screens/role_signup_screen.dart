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
  bool _compact = false;

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
      if (_role != "inspector" && password.length < 4) {
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
        // "Buy & Sell" maps to buyer role in backend
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
        path = "/public/inspector-requests";
        payload = {
          "name": name,
          "email": email,
          "phone": phone,
          "notes": _inspectorReason.text.trim(),
        };
      }

      if (kDebugMode) {
        final keys = payload.keys.where((k) => k.toLowerCase() != "password").toList();
        debugPrint("Signup payload keys: $keys role=$_role path=$path");
      }

      final res = await ApiClient.instance.postJson(ApiConfig.api(path), payload);

      if (_role == "inspector") {
        if (res is Map && res["ok"] == true) {
          _toast("Inspector request submitted");
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => PendingApprovalScreen(role: _role)),
          );
          return;
        }
        if (res is Map && res["message"] != null) {
          _toast(res["message"].toString());
          return;
        }
        _toast("Request failed");
        return;
      }

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
    bool primary = false,
  }) {
    final selected = _role == value;
    final double cardPadding = _compact ? 14 : 16;
    final borderColor = selected
        ? Colors.black
        : primary
            ? const Color(0xFF0F172A)
            : const Color(0xFFE5E7EB);
    final bg = selected
        ? const Color(0xFF0B1220)
        : primary
            ? const Color(0xFFF8FAFC)
            : Colors.white;
    return InkWell(
      onTap: _loading ? null : () => setState(() => _role = value),
      borderRadius: BorderRadius.circular(primary ? 18 : 16),
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(primary ? 18 : 16),
          border: Border.all(color: borderColor),
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
              width: primary ? (_compact ? 42 : 48) : (_compact ? 40 : 44),
              height: primary ? (_compact ? 42 : 48) : (_compact ? 40 : 44),
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
                      fontSize: _compact ? 14.5 : 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      height: 1.25,
                      color: selected ? Colors.white.withOpacity(0.9) : const Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                      fontSize: _compact ? 11.5 : 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (primary)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withOpacity(0.12) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "Recommended",
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF0F172A),
                    fontSize: _compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                  ),
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
    _compact = MediaQuery.of(context).size.width < 360;
    return Scaffold(
      appBar: AppBar(title: const Text("Choose your path")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Choose your role",
                style: TextStyle(
                  fontSize: _compact ? 20 : 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Pick how you want to use FlipTrybe. You can upgrade roles later, but this helps us set you up right from day one.",
                style: TextStyle(color: Colors.black.withOpacity(0.65), height: 1.35),
              ),
              const SizedBox(height: 14),

              _roleCard(
                value: "buyer",
                title: "Buy & Sell",
                subtitle: "Buy and sell items safely with escrow and delivery confirmation.",
                icon: Icons.shopping_bag_rounded,
                primary: true,
              ),
              const SizedBox(height: 10),
              _roleCard(
                value: "merchant",
                title: "Merchant",
                subtitle: "List items, manage orders, and grow followers.",
                icon: Icons.storefront_rounded,
              ),
              const SizedBox(height: 10),
              _roleCard(
                value: "driver",
                title: "Driver",
                subtitle: "Deliver orders and earn. Access driver jobs based on locality.",
                icon: Icons.delivery_dining_rounded,
              ),
              const SizedBox(height: 10),
              _roleCard(
                value: "inspector",
                title: "Inspector",
                subtitle: "Verify items and approve inspection tasks.",
                icon: Icons.verified_user_rounded,
              ),

              const Divider(height: 28),

              _field(_name, "Full name"),
              _field(_email, "Email", keyboard: TextInputType.emailAddress),
              if (_role != "inspector") _field(_password, "Password"),
              _field(_phone, "Phone", keyboard: TextInputType.phone),

              if (_role == "merchant" || _role == "driver") ...[
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
                    ? "Tip: You can start buying and selling instantly."
                    : "Note: ${_role.toUpperCase()} activation is reviewed for safety. You'll still have access to Buy & Sell while we verify you.",
                style: TextStyle(color: Colors.black.withOpacity(0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
