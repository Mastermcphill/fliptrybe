import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_config.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/token_storage.dart';
import '../ui/components/ft_components.dart';
import '../utils/auth_navigation.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';
import 'following_merchants_screen.dart';
import 'investor_metrics_screen.dart';
import 'invite_earn_screen.dart';
import 'kyc_demo_screen.dart';
import 'marketplace/favorites_screen.dart';
import 'marketplace/saved_searches_screen.dart';
import 'merchant_listings_demo_screen.dart';
import 'notifications_inbox_screen.dart';
import 'orders_screen.dart';
import 'personal_analytics_screen.dart';
import 'receipts_screen.dart';
import 'report_problem_screen.dart';
import 'settings_demo_screen.dart';
import 'support_chat_screen.dart';
import 'support_tickets_screen.dart';
import 'wallet_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final NotificationService _notifications = NotificationService.instance;

  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _primeNotifications();
  }

  Future<void> _primeNotifications() async {
    try {
      await _notifications.loadInbox(refresh: false);
    } catch (_) {
      // non-blocking
    }
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
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await ApiService.getProfile();
      if (!mounted) return;
      if (!_looksLikeUserProfile(data)) {
        setState(() {
          _profile = null;
          _loading = false;
          _error = data['message']?.toString() ?? 'Session not available';
        });
        return;
      }
      setState(() {
        _profile = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = UIFeedback.mapDioErrorToMessage(e);
      setState(() {
        _profile = null;
        _loading = false;
        _error = message;
      });
      UIFeedback.showErrorSnack(context, message);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsDemoScreen()),
    );
    if (!mounted) return;
    _loadProfile();
  }

  Future<void> _handleLogout() async {
    await logoutToLanding(context);
  }

  String _apiHostSummary() {
    final uri = Uri.tryParse(ApiConfig.baseUrl);
    final host = uri?.host ?? ApiConfig.baseUrl;
    if (host.length <= 24) return host;
    return '${host.substring(0, 12)}...${host.substring(host.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    final role = (_profile?['role'] ?? 'buyer').toString().toLowerCase();
    final isMerchant = role == 'merchant' || role == 'admin';
    final isInvestorRole = role == 'admin' || role == 'investor';
    final isVerified = _profile?['is_verified'] == true;
    final balance = double.tryParse('${_profile?['wallet_balance'] ?? 0}') ?? 0;
    final tierLabel = (_profile?['tier'] ?? 'Novice').toString();
    final name = (_profile?['name'] ?? 'FlipTrybe User').toString();

    return FTScaffold(
      title: 'My Hub',
      onRefresh: _loadProfile,
      actions: [
        Semantics(
          label: 'Appearance',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.palette_outlined),
            onPressed: _openSettings,
          ),
        ),
        Semantics(
          label: 'Sign out',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
          ),
        ),
      ],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _loadProfile,
        empty: _profile == null,
        loadingState: FTSkeletonList(
          itemCount: 4,
          itemBuilder: (context, index) => const FTSkeletonCard(height: 96),
        ),
        emptyState: FTEmptyState(
          icon: Icons.person_off_outlined,
          title: 'Session not available',
          subtitle: _error ?? 'Please sign in again.',
          primaryCtaText: 'Sign in',
          onPrimaryCta: _handleLogout,
          secondaryCtaText: 'Retry',
          onSecondaryCta: _loadProfile,
        ),
        child: ListView(
          children: [
            FTSection(
              title: 'Account summary',
              subtitle: '$name - Tier $tierLabel',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatNaira(balance),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isVerified
                        ? 'Phone verified'
                        : 'Verify your phone to unlock protected actions.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isVerified
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Quick actions',
              child: FTPrimaryCtaRow(
                primaryLabel: 'Wallet',
                onPrimary: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WalletScreen()),
                  );
                },
                secondaryLabel: 'Receipts',
                onSecondary: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReceiptsScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Activity',
              child: Column(
                children: [
                  FTListTile(
                    leading: const Icon(Icons.shopping_bag_outlined),
                    title: 'My Orders',
                    subtitle: 'Track order progress and delivery timelines.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OrdersScreen()),
                    ),
                  ),
                  FTListTile(
                    leading: const Icon(Icons.people_outline),
                    title: 'Following merchants',
                    subtitle: 'Stay updated on merchants you follow.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FollowingMerchantsScreen(),
                      ),
                    ),
                  ),
                  FTListTile(
                    leading: const Icon(Icons.bookmarks_outlined),
                    title: 'Saved searches',
                    subtitle: 'Reopen your saved discovery filters quickly.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SavedSearchesScreen(),
                      ),
                    ),
                  ),
                  FTListTile(
                    leading: const Icon(Icons.favorite_border),
                    title: 'Favorites',
                    subtitle: 'Watchlist of listings you liked.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const FavoritesScreen()),
                    ),
                  ),
                  FTListTile(
                    leading: const Icon(Icons.card_giftcard_outlined),
                    title: 'Invite & Earn',
                    subtitle: 'Share your referral code and track rewards.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const InviteEarnScreen(),
                      ),
                    ),
                  ),
                  if (isMerchant)
                    FTListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: 'My Listings',
                      subtitle: 'Manage your marketplace inventory.',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MerchantListingsDemoScreen(),
                        ),
                      ),
                    ),
                  FTListTile(
                    leading: const Icon(Icons.analytics_outlined),
                    title: 'Analytics',
                    subtitle: isInvestorRole
                        ? 'Investor and growth metrics.'
                        : isMerchant
                            ? 'Sales, commission and conversion trends.'
                            : 'Purchases and spending insights.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => isInvestorRole
                            ? const InvestorMetricsScreen()
                            : PersonalAnalyticsScreen(role: role),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Support',
              child: Column(
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: _notifications.unreadCount,
                    builder: (context, unread, _) => FTListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: 'Notification Center',
                      subtitle: unread > 0
                          ? '$unread unread updates'
                          : 'View alerts and product updates.',
                      badgeText: unread > 0 ? '$unread' : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationsInboxScreen(),
                        ),
                      ),
                    ),
                  ),
                  FTListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: 'Support tickets',
                    subtitle: 'View and manage your support tickets.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SupportTicketsScreen(),
                      ),
                    ),
                  ),
                  FTListTile(
                    leading: const Icon(Icons.chat_outlined),
                    title: 'Support chat',
                    subtitle: 'Chat with support for urgent help.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SupportChatScreen(),
                      ),
                    ),
                  ),
                  FTListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: 'Report a problem',
                    subtitle: 'Send diagnostics with your issue report.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ReportProblemScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Security & appearance',
              child: Column(
                children: [
                  FTListTile(
                    leading: const Icon(Icons.phonelink_lock_outlined),
                    title: 'Phone verification',
                    subtitle: isVerified
                        ? 'Your phone is verified.'
                        : 'Complete OTP verification to unlock protected actions.',
                    onTap: null,
                  ),
                  FTListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: 'KYC verification',
                    subtitle: 'Increase limits and tier eligibility.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const KycDemoScreen()),
                    ),
                  ),
                  Semantics(
                    label: 'Appearance',
                    button: true,
                    child: FTListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: 'Appearance',
                      subtitle: 'Theme mode and background palette.',
                      onTap: _openSettings,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'About',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App version: ${ApiConfig.appVersion}'),
                  Text('API host: ${_apiHostSummary()}'),
                  Text(
                    "Git SHA: ${String.fromEnvironment('GIT_SHA', defaultValue: 'dev')}",
                  ),
                  const SizedBox(height: 10),
                  FTButton(
                    label: 'Sign out',
                    variant: FTButtonVariant.destructive,
                    expand: true,
                    onPressed: _handleLogout,
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 8),
                    FTButton(
                      label: 'Auth debug tools',
                      variant: FTButtonVariant.ghost,
                      expand: true,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AuthDebugScreen(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
      return '${t.substring(0, 12)}...${t.substring(t.length - 6)}';
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
    await logoutToLanding(context);
    if (!mounted) return;
    setState(() {
      _tokenPresent = false;
      _tokenPreview = '***';
      _checking = false;
    });
  }

  Future<void> _recheckSession() async {
    if (_checking) return;
    setState(() => _checking = true);
    final token = await _resolveToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() => _checking = false);
      UIFeedback.showErrorSnack(context, 'No token found. Log in first.');
      return;
    }

    ApiService.setToken(token);
    try {
      final res = await ApiService.getProfileResponse();
      if (res.statusCode == 401 && mounted) {
        await logoutToLanding(context);
      }
    } finally {
      if (mounted) {
        await _loadTokenInfo();
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _copyPreview() async {
    await Clipboard.setData(ClipboardData(text: _tokenPreview));
    if (!mounted) return;
    UIFeedback.showSuccessSnack(context, 'Token preview copied.');
  }

  @override
  Widget build(BuildContext context) {
    final status = ApiService.lastMeStatusCode;
    final statusText = status == null ? 'Not checked' : status.toString();
    final lastAt = _formatTimestamp(ApiService.lastMeAt);
    final lastError = ApiService.lastAuthError ?? 'None';

    return FTScaffold(
      title: 'Auth Debug',
      child: ListView(
        children: [
          FTSection(
            title: 'Session diagnostics',
            child: Column(
              children: [
                FTListTile(
                  title: 'Token present',
                  subtitle: _tokenPresent ? 'Yes' : 'No',
                  onTap: null,
                ),
                FTListTile(
                  title: 'Token preview',
                  subtitle: _tokenPreview,
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: _copyPreview,
                  ),
                  onTap: null,
                ),
                FTListTile(
                  title: 'Last /api/auth/me',
                  subtitle: '$statusText @ $lastAt',
                  onTap: null,
                ),
                FTListTile(
                  title: 'Last auth error',
                  subtitle: lastError,
                  onTap: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FTAsyncButton(
            label: _checking ? 'Checking...' : 'Recheck session',
            icon: Icons.refresh,
            externalLoading: _checking,
            onPressed: _checking ? null : _recheckSession,
          ),
          const SizedBox(height: 8),
          FTButton(
            label: 'Clear token',
            icon: Icons.logout,
            variant: FTButtonVariant.destructive,
            expand: true,
            onPressed: _checking ? null : _clearToken,
          ),
        ],
      ),
    );
  }
}
