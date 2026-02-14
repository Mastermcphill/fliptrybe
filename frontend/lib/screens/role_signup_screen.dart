import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';
import '../constants/ng_states.dart';
import '../ui/components/ft_components.dart';
import '../utils/ft_routes.dart';
import '../utils/ui_feedback.dart';
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
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _phoneFocus = FocusNode();

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
    if (!mounted) return;
    UIFeedback.showErrorSnack(context, msg);
  }

  bool _responseIndicatesPending(Map<dynamic, dynamic> res) {
    final request = res['request'];
    if (request is Map) {
      final status = (request['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'pending' || status == 'pending_approval') return true;
    }
    final status = (res['status'] ?? '').toString().trim().toLowerCase();
    if (status == 'pending' || status == 'pending_approval') return true;
    final message = (res['message'] ?? '').toString().toLowerCase();
    if (message.contains('pending') ||
        message.contains('admin-mediated') ||
        message.contains('admin approval')) {
      return true;
    }
    return false;
  }

  Future<void> _signup() async {
    setState(() => _loading = true);

    try {
      final name = _name.text.trim();
      final email = _email.text.trim();
      final password = _password.text.trim();
      final phone = _phone.text.replaceAll(RegExp(r'\s+'), '').trim();

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
        final keys =
            payload.keys.where((k) => k.toLowerCase() != "password").toList();
        debugPrint("Signup payload keys: $keys role=$_role path=$path");
      }

      final res =
          await ApiClient.instance.postJson(ApiConfig.api(path), payload);

      if (res is Map) {
        final token = (res["token"] ?? "").toString();
        final hasToken = token.isNotEmpty;
        if (hasToken) {
          await ApiService.persistAuthPayload(
              res.map((k, v) => MapEntry('$k', v)));
        }

        if (_responseIndicatesPending(res)) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            FTRoutes.page(
              child: PendingApprovalScreen(role: _role),
            ),
          );
          return;
        }

        if (hasToken) {
          if (!mounted) return;
          _toast("Account created");
          Navigator.pop(context, true);
          return;
        }

        if (res["message"] != null) {
          _toast(res["message"].toString());
          return;
        }
        _toast("Signup failed");
      } else {
        _toast("Signup failed");
      }
    } catch (e) {
      _toast(UIFeedback.mapDioErrorToMessage(e));
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
    String? badge,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _role == value;
    final double cardPadding = _compact ? 14 : 16;
    final borderColor = selected
        ? scheme.primary
        : primary
            ? scheme.outline
            : scheme.outlineVariant;
    final bg = selected
        ? scheme.primaryContainer
        : primary
            ? scheme.surfaceContainerLow
            : scheme.surface;
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
                    color: scheme.shadow.withValues(alpha: 0.12),
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
                color: selected
                    ? scheme.primary.withValues(alpha: 0.18)
                    : scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSecondaryContainer,
              ),
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
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                      fontSize: _compact ? 14.5 : 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      height: 1.25,
                      color: selected
                          ? scheme.onPrimaryContainer.withValues(alpha: 0.92)
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: _compact ? 11.5 : 12.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (badge != null && badge.trim().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: selected
                                ? scheme.primary.withValues(alpha: 0.18)
                                : scheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: selected
                                  ? scheme.onPrimaryContainer
                                  : scheme.onTertiaryContainer,
                              fontSize: _compact ? 10 : 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        "Tap to continue",
                        style: TextStyle(
                          color: selected
                              ? scheme.onPrimaryContainer
                                  .withValues(alpha: 0.92)
                              : scheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: _compact ? 10.5 : 11.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (primary)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.18)
                      : scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "Recommended",
                  style: TextStyle(
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onTertiaryContainer,
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

  Widget _field(
    TextEditingController c,
    String label, {
    TextInputType? keyboard,
    FocusNode? focusNode,
    FocusNode? nextFocusNode,
    bool obscure = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: obscure
          ? FTPasswordField(
              controller: c,
              focusNode: focusNode,
              nextFocusNode: nextFocusNode,
              labelText: label,
              enabled: !_loading,
            )
          : FTTextField(
              controller: c,
              focusNode: focusNode,
              nextFocusNode: nextFocusNode,
              keyboardType: keyboard,
              labelText: label,
              enabled: !_loading,
              maxLines: maxLines,
            ),
    );
  }

  Widget _stateDropdown() {
    final current = _state.text.trim().isEmpty ? 'Lagos' : _state.text.trim();
    if (current != _state.text.trim()) {
      _state.text = current;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FTDropDownField<String>(
        initialValue: nigeriaStates.contains(current) ? current : 'Lagos',
        labelText: 'State',
        items: nigeriaStates
            .map((s) => DropdownMenuItem<String>(
                value: s, child: Text(displayState(s))))
            .toList(),
        onChanged: _loading
            ? null
            : (v) {
                if (v == null) return;
                setState(() => _state.text = v);
              },
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _phoneFocus.dispose();
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
    final scheme = Theme.of(context).colorScheme;
    return FTScaffold(
      title: "Choose your path",
      child: SingleChildScrollView(
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
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            _roleCard(
              value: "buyer",
              title: "Buy & Sell",
              subtitle:
                  "Buy and sell, track orders, and chat admin for support.",
              icon: Icons.shopping_bag_rounded,
              primary: true,
            ),
            const SizedBox(height: 10),
            _roleCard(
              value: "merchant",
              title: "Merchant",
              subtitle:
                  "List products and manage sales. Verified email required for sensitive actions.",
              icon: Icons.storefront_rounded,
              badge: "Requires admin approval",
            ),
            const SizedBox(height: 10),
            _roleCard(
              value: "driver",
              title: "Driver",
              subtitle:
                  "Accept delivery jobs and complete pickup/dropoff code confirmations.",
              icon: Icons.delivery_dining_rounded,
              badge: "Requires admin approval",
            ),
            const SizedBox(height: 10),
            _roleCard(
              value: "inspector",
              title: "Inspector",
              subtitle:
                  "Handle inspection tickets and submit inspection outcomes.",
              icon: Icons.verified_user_rounded,
              badge: "Requires admin approval",
            ),
            const Divider(height: 28),
            _field(
              _name,
              "Full name",
              focusNode: _nameFocus,
              nextFocusNode: _emailFocus,
            ),
            _field(
              _email,
              "Email",
              keyboard: TextInputType.emailAddress,
              focusNode: _emailFocus,
              nextFocusNode: _passwordFocus,
            ),
            _field(
              _password,
              "Password",
              focusNode: _passwordFocus,
              nextFocusNode: _phoneFocus,
              obscure: true,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FTPhoneField(
                controller: _phone,
                focusNode: _phoneFocus,
                labelText: 'Phone',
                enabled: !_loading,
              ),
            ),
            if (_role == "merchant" ||
                _role == "driver" ||
                _role == "inspector") ...[
              const SizedBox(height: 6),
              _stateDropdown(),
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
            Semantics(
              label: "Create account action",
              button: true,
              child: FTAsyncButton(
                label: "Create account",
                variant: FTButtonVariant.primary,
                icon: Icons.lock_rounded,
                externalLoading: _loading,
                onPressed: _loading ? null : _signup,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _role == "buyer"
                  ? "Tip: You can start buying and selling instantly."
                  : "Note: ${_role.toUpperCase()} activation is reviewed for safety. You'll still have access to Buy & Sell while we verify you.",
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
