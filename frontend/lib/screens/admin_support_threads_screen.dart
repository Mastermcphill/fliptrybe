import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';
import '../ui/admin/admin_data_card.dart';
import '../ui/admin/admin_scaffold.dart';
import '../ui/components/ft_components.dart';
import '../ui/foundation/app_tokens.dart';
import 'admin_support_thread_screen.dart';

class AdminSupportThreadsScreen extends StatefulWidget {
  const AdminSupportThreadsScreen({super.key});

  @override
  State<AdminSupportThreadsScreen> createState() =>
      _AdminSupportThreadsScreenState();
}

class _AdminSupportThreadsScreenState extends State<AdminSupportThreadsScreen> {
  bool _authChecking = true;
  bool _isAdmin = false;
  bool _loading = false;
  String? _error;
  List<dynamic> _threads = const [];

  @override
  void initState() {
    super.initState();
    _ensureAdmin();
  }

  Future<void> _ensureAdmin() async {
    try {
      final me = await ApiService.getProfile();
      final role = (me['role'] ?? '').toString().trim().toLowerCase();
      if (!mounted) return;
      if (role == 'admin') {
        setState(() {
          _isAdmin = true;
          _authChecking = false;
        });
        await _load();
        return;
      }
      setState(() {
        _authChecking = false;
        _isAdmin = false;
        _error = 'Admin access required.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authChecking = false;
        _isAdmin = false;
        _error = 'Unable to verify admin access: $e';
      });
    }
  }

  Future<void> _load() async {
    if (!_isAdmin) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.dio
          .get(ApiConfig.api('/admin/support/threads'));
      final data = res.data;
      final items = (data is Map && data['threads'] is List)
          ? (data['threads'] as List)
          : <dynamic>[];
      if (!mounted) return;
      setState(() => _threads = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_authChecking) {
      return const AdminScaffold(
        title: 'Support Threads',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isAdmin) {
      return AdminScaffold(
        title: 'Support Threads',
        child: FTErrorState(message: _error ?? 'Admin access required.'),
      );
    }
    return AdminScaffold(
      title: 'Support Threads',
      onRefresh: _load,
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: _threads.isEmpty,
        loadingState: ListView(
          children: const [
            FTListCardSkeleton(withImage: false),
            SizedBox(height: AppTokens.s12),
            FTListCardSkeleton(withImage: false),
            SizedBox(height: AppTokens.s12),
            FTListCardSkeleton(withImage: false),
          ],
        ),
        emptyState: FTEmptyState(
          icon: Icons.support_agent_outlined,
          title: 'No support threads',
          subtitle:
              'Support conversations will appear here when users send messages.',
          actionLabel: 'Refresh',
          onAction: _load,
        ),
        child: ListView.separated(
          itemCount: _threads.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppTokens.s12),
          itemBuilder: (context, i) {
            final raw = _threads[i];
            if (raw is! Map) return const SizedBox.shrink();
            final m = Map<String, dynamic>.from(raw);
            final id = m['user_id'];
            final name = (m['name'] ?? '').toString().trim();
            final email = (m['email'] ?? '').toString().trim();
            final displayName = name.isEmpty ? email : name;
            final count = (m['count'] ?? 0).toString();
            final lastAt = (m['last_at'] ?? '').toString();
            return AdminDataCard(
              title: displayName,
              subtitle: email.isEmpty ? lastAt : '$email - $lastAt',
              trailing: FTBadge(text: 'Msg $count'),
              child: FTTile(
                leadingWidget: CircleAvatar(
                  radius: 18,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                titleWidget: Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: 'Open thread and respond',
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final userId =
                      id is int ? id : int.tryParse(id?.toString() ?? '');
                  if (userId == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminSupportThreadScreen(
                        userId: userId,
                        userEmail: email,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
