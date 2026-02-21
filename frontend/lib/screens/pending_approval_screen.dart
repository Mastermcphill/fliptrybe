import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';
import '../ui/components/ft_components.dart';
import '../ui/foundation/tokens/ft_spacing.dart';
import '../utils/ft_routes.dart';
import 'landing_screen.dart';
import 'login_screen.dart';

class PendingApprovalScreen extends StatefulWidget {
  final String role;

  const PendingApprovalScreen({super.key, required this.role});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _loading = true;
  String _status = 'pending';
  String? _reason;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  String get _targetRole => widget.role.trim().toLowerCase();

  String _label() {
    switch (_targetRole) {
      case 'merchant':
        return 'Merchant';
      case 'driver':
        return 'Driver';
      case 'inspector':
        return 'Inspector';
      default:
        return 'Account';
    }
  }

  bool _hasProfileShape(Map<String, dynamic> me) {
    final id = me['id'];
    final role = me['role'];
    return id != null && role != null;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = await ApiService.getProfile();
      String currentRole = '';
      if (_hasProfileShape(me)) {
        currentRole = (me['role'] ?? '').toString().trim().toLowerCase();
        if (currentRole == _targetRole) {
          if (!mounted) return;
          setState(() {
            _status = 'approved';
            _reason = null;
            _loading = false;
          });
          return;
        }
      }

      final res =
          await ApiClient.instance.dio.get(ApiConfig.api('/role-requests/me'));
      final data = res.data;
      if (data is Map && data['request'] is Map) {
        final req = Map<String, dynamic>.from(data['request'] as Map);
        final status = (req['status'] ?? '').toString().trim().toLowerCase();
        if (!mounted) return;
        setState(() {
          _status = status.isEmpty ? 'pending' : status;
          _reason =
              (req['admin_note'] ?? req['reason'] ?? '').toString().trim();
          _loading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _status = currentRole == _targetRole ? 'approved' : 'pending';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'pending';
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _titleText() {
    final label = _label();
    if (_status == 'approved') return '$label request approved';
    if (_status == 'rejected') return '$label request rejected';
    return '$label application received';
  }

  String _bodyText() {
    if (_status == 'approved') {
      return 'Your role has been approved. Log out and back in to refresh all role-based features.';
    }
    if (_status == 'rejected') {
      final reason = (_reason ?? '').trim();
      if (reason.isNotEmpty) return 'Your request was rejected: $reason';
      return 'Your request was rejected. You can submit a new one.';
    }
    return 'Your request is pending admin approval. You can still browse while we review it.';
  }

  void _goLogin() {
    Navigator.of(context).pushReplacement(
      FTRoutes.page(child: const LoginScreen()),
    );
  }

  void _goMarketplace() {
    Navigator.of(context).pushReplacement(
      FTRoutes.page(
        child: LandingScreen(
          onLogin: () {
            Navigator.of(context).push(
              FTRoutes.page(child: const LoginScreen()),
            );
          },
          onSignup: () {
            Navigator.of(context).push(
              FTRoutes.page(child: const LoginScreen()),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Pending Approval',
      child: _loading
          ? FTSkeletonList(
              itemCount: 1,
              itemBuilder: (_, __) => const FTSkeletonCard(height: 260),
            )
          : ListView(
              children: [
                FTCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleText(),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: FTSpacing.xs),
                      Text(
                        _bodyText(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      if ((_error ?? '').isNotEmpty) ...[
                        const SizedBox(height: FTSpacing.xs),
                        FTBadge(
                          text: 'Status warning',
                          backgroundColor:
                              Theme.of(context).colorScheme.errorContainer,
                          foregroundColor:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(height: FTSpacing.xs),
                        Text(
                          _error!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                        ),
                      ],
                      const SizedBox(height: FTSpacing.sm),
                      FTButton(
                        label: 'Refresh status',
                        expand: true,
                        onPressed: _refresh,
                      ),
                      const SizedBox(height: FTSpacing.xs),
                      FTButton(
                        label: _status == 'approved'
                            ? 'Continue to Login'
                            : 'Go to Login',
                        expand: true,
                        variant: FTButtonVariant.secondary,
                        onPressed: _goLogin,
                      ),
                      const SizedBox(height: FTSpacing.xs),
                      FTButton(
                        label: 'Back to Marketplace',
                        expand: true,
                        variant: FTButtonVariant.ghost,
                        onPressed: _goMarketplace,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
