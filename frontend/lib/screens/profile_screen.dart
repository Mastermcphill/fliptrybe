import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'driver_profile_screen.dart';
import '../services/api_service.dart';
import '../services/api_config.dart';
import '../services/token_storage.dart';
import 'landing_screen.dart';
import 'login_screen.dart';
import 'role_signup_screen.dart';
import 'heatmap_screen.dart';
import 'shortlets_screen.dart';
import 'fees_demo_screen.dart';
import 'shortlet_screen.dart';
import 'merchant_listings_demo_screen.dart';
import 'settings_demo_screen.dart';
import 'notifications_inbox_screen.dart';
import 'driver_jobs_screen.dart';
import 'admin_screen.dart';
import 'wallet_screen.dart';
import 'merchants_screen.dart';
import 'notifications_screen.dart';
import 'receipts_screen.dart';
import 'support_tickets_screen.dart';
import 'kyc_demo_screen.dart';
import 'admin_broadcast_screen.dart';
import 'leaderboards_screen.dart';
import 'orders_screen.dart';
import 'investor_metrics_screen.dart';
import 'sales_analytics_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  bool _looksLikeUserProfile(Map<String, dynamic> data) {
    final id = data['id'];
    final email = data['email'];
    final name = data['name'];

    final emailOk = email is String && email.trim().isNotEmpty;
    final nameOk = name is String && name.trim().isNotEmpty;

    return id != null && (emailOk || nameOk);
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ApiService.getProfile();

      // If backend returns a 401 message map, treat it as "not logged in"
      final hasUserShape = _looksLikeUserProfile(data);

      if (!hasUserShape) {
        if (!mounted) return;
        setState(() {
          _profile = null;
          _isLoading = false;
          _error = data['message']?.toString() ?? "Not logged in";
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _profile = data;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _handleLogout() async {
    // Clear token + auth header
    await TokenStorage().clear();
    ApiService.setToken(null);
    ApiService.lastMeStatusCode = null;
    ApiService.lastMeAt = null;
    ApiService.lastAuthError = null;

    // Go back to landing screen without relying on named routes
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LandingScreen(
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
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Default values if loading or missing profile
    final String name = _profile?['name']?.toString() ?? "FlipTrybe User";
    final double balance =
        double.tryParse(_profile?['wallet_balance']?.toString() ?? "0") ?? 0.0;

    final dynamic verifiedRaw = _profile?['is_verified'];
    final bool isVerified = verifiedRaw == true;
    final kycTierRaw = _profile?['kyc_tier'];
    final int kycTier = (kycTierRaw is int) ? kycTierRaw : int.tryParse(kycTierRaw?.toString() ?? '0') ?? 0;
    final bool isAvailable = _profile?['is_available'] == true;

    final String tier = _profile?['tier']?.toString() ?? "Novice";

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Hub", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsDemoScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _handleLogout,
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00C853)),
            )
          : (_error != null)
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const SizedBox(height: 60),
                    const Icon(Icons.lock_outline, size: 44),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text(
                        "Session not available",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _loadProfile,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Try again"),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: TextButton(
                        onPressed: _handleLogout,
                        child: const Text("Go to Login"),
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // 1. WALLET CARD
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00C853), Color(0xFF009624)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00C853).withOpacity(0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 10),
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Escrow Balance",
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "₦${balance.toStringAsFixed(2)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    tier,
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                )
                              ],
                            )
                          ],
                        ),
                      ),

                      const SizedBox(height: 25),

                      // 2. ACTION GRID
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionButton(Icons.account_balance_wallet, "Withdraw"),
                          _buildActionButton(Icons.history, "History", onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiptsScreen()));
                          }),
                          _buildActionButton(
                            Icons.verified_user,
                            "Verify ID",
                            isAlert: !isVerified,
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const KycDemoScreen()));
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 30),

                      // 3. MENU LIST
                      _buildMenuItem(Icons.shopping_bag, "My Orders", onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()));
                      }),
                      _buildMenuItem(Icons.store, "My Listings",
                          onTap: (() {
                            final role = (_profile?["role"] ?? "buyer").toString();
                            final isMerchant = role == "merchant" || role == "admin";
                            if (!isMerchant) return null;
                            return () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const MerchantListingsDemoScreen()));
                            };
                          })(),
                      ),
                      _buildMenuItem(Icons.analytics, "Sales Analytics", onTap: () {
                        final role = (_profile?["role"] ?? "buyer").toString();
                        if (role == "merchant" || role == "admin") {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesAnalyticsScreen()));
                        } else {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const InvestorMetricsScreen()));
                        }
                      }),
                      _buildMenuItem(Icons.support_agent, "Help & Disputes", onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportTicketsScreen()));
                      }),

                      const SizedBox(height: 20),

                      if (kDebugMode) ...[
                        const SizedBox(height: 6),
                        ListTile(
                          leading: const Icon(Icons.bug_report_outlined, color: Colors.orange),
                          title: const Text('Auth Debug', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('Dev-only auth diagnostics', style: TextStyle(color: Colors.grey)),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthDebugScreen()));
                          },
                        ),
                      ],

                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text("Log Out", style: TextStyle(color: Colors.red)),
                        onTap: _handleLogout,
                      ),
                    ],
                  ),
                ),
      backgroundColor: Colors.black,
    );
  }

  Widget _buildActionButton(IconData icon, String label, {bool isAlert = false, VoidCallback? onTap}) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Stack(
            children: [
              Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            if (isAlert)
              const Positioned(
                right: 0,
                top: 0,
                child: CircleAvatar(radius: 6, backgroundColor: Colors.red),
              )
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildMenuItem(IconData icon, String title, {VoidCallback? onTap}) {
    final enabled = onTap != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: enabled ? null : const Text('In next release', style: TextStyle(color: Colors.grey)),
        trailing: Icon(enabled ? Icons.arrow_forward_ios : Icons.lock_outline, color: Colors.grey, size: 16),
        onTap: onTap,
      ),
    );
  }
}


class AuthDebugScreen extends StatefulWidget {
  const AuthDebugScreen({super.key});

  @override
  State<AuthDebugScreen> createState() => _AuthDebugScreenState();
}

class _AuthDebugScreenState extends State<AuthDebugScreen> {
  bool _checking = false;
  bool _tokenPresent = false;
  String _tokenPreview = '***';

  @override
  void initState() {
    super.initState();
    _loadTokenInfo();
  }

  String _formatPreview(String? token) {
    final t = token?.trim() ?? '';
    if (t.isEmpty) return '***';
    if (t.length > 20) {
      return '${t.substring(0, 12)}?${t.substring(t.length - 6)}';
    }
    return '***';
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return 'Not checked';
    return dt.toLocal().toString();
  }

  Future<String?> _resolveToken() async {
    final inMemory = ApiService.token;
    if (inMemory != null && inMemory.trim().isNotEmpty) return inMemory.trim();
    final stored = await TokenStorage().readToken();
    return stored?.trim();
  }

  Future<void> _loadTokenInfo() async {
    final token = await _resolveToken();
    if (!mounted) return;
    final present = token != null && token.isNotEmpty;
    setState(() {
      _tokenPresent = present;
      _tokenPreview = _formatPreview(token);
    });
  }

  Future<void> _clearToken() async {
    if (_checking) return;
    setState(() => _checking = true);
    await TokenStorage().clear();
    ApiService.setToken(null);
    if (!mounted) return;
    setState(() {
      _tokenPresent = false;
      _tokenPreview = '***';
      _checking = false;
    });
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _recheckSession() async {
    if (_checking) return;
    setState(() => _checking = true);
    final token = await _resolveToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No token found. Login first.')),
      );
      return;
    }

    ApiService.setToken(token);
    try {
      final res = await ApiService.getProfileResponse();
      if (res.statusCode == 401) {
        await TokenStorage().clear();
        ApiService.setToken(null);
        if (!mounted) return;
        setState(() {
          _tokenPresent = false;
          _tokenPreview = '***';
        });
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }
    } finally {
      if (!mounted) return;
      await _loadTokenInfo();
      setState(() => _checking = false);
    }
  }

  Future<void> _copyPreview() async {
    await Clipboard.setData(ClipboardData(text: _tokenPreview));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Token preview copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ApiService.lastMeStatusCode;
    final statusText = status == null ? 'Not checked' : status.toString();
    final lastAt = _formatTimestamp(ApiService.lastMeAt);
    final lastError = ApiService.lastAuthError ?? 'None';

    return Scaffold(
      appBar: AppBar(title: const Text('Auth Debug')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Token present'),
            subtitle: Text(_tokenPresent ? 'Yes' : 'No'),
          ),
          ListTile(
            title: const Text('Token preview'),
            subtitle: Text(_tokenPreview),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyPreview,
            ),
          ),
          ListTile(
            title: const Text('Last /api/auth/me'),
            subtitle: Text('$statusText @ $lastAt'),
          ),
          ListTile(
            title: const Text('Last auth error'),
            subtitle: Text(lastError),
          ),
          ListTile(
            title: const Text('Base API URL'),
            subtitle: Text(ApiConfig.baseUrl),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _checking ? null : _recheckSession,
            icon: const Icon(Icons.refresh),
            label: Text(_checking ? 'Checking...' : 'Recheck session'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _checking ? null : _clearToken,
            icon: const Icon(Icons.logout),
            label: const Text('Clear token'),
          ),
        ],
      ),
    );
  }
}
