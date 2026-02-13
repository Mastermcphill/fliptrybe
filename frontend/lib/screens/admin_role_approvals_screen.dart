import 'package:flutter/material.dart';

import '../services/admin_role_service.dart';
import '../ui/admin/admin_scaffold.dart';
import '../ui/components/ft_components.dart';
import '../ui/foundation/app_tokens.dart';

class AdminRoleApprovalsScreen extends StatefulWidget {
  const AdminRoleApprovalsScreen({super.key});

  @override
  State<AdminRoleApprovalsScreen> createState() => _AdminRoleApprovalsScreenState();
}

class _AdminRoleApprovalsScreenState extends State<AdminRoleApprovalsScreen> {
  final _svc = AdminRoleService();
  late Future<List<dynamic>> _items;
  String _status = 'PENDING';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = _svc.pending(status: _status);
  }

  void _reload() {
    setState(() => _items = _svc.pending(status: _status));
  }

  Future<void> _approve(Map<String, dynamic> item) async {
    if (_busy) return;
    final reqId = item['id'] is int ? item['id'] as int : int.tryParse((item['id'] ?? '').toString());
    if (reqId == null) return;
    setState(() => _busy = true);
    final res = await _svc.approve(requestId: reqId);
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = res['ok'] == true;
    final msg = (res['message'] ?? (ok ? 'Approved' : 'Approve failed')).toString();
    FTToast.show(context, msg);
    if (ok) _reload();
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    if (_busy) return;
    final reqId = item['id'] is int ? item['id'] as int : int.tryParse((item['id'] ?? '').toString());
    if (reqId == null) return;
    setState(() => _busy = true);
    final res = await _svc.reject(requestId: reqId);
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = res['ok'] == true;
    final msg = (res['message'] ?? (ok ? 'Rejected' : 'Reject failed')).toString();
    FTToast.show(context, msg);
    if (ok) _reload();
  }

  Widget _statusChip(String value) {
    return ChoiceChip(
      label: Text(value[0] + value.substring(1).toLowerCase()),
      selected: _status == value,
      onSelected: (selected) {
        if (!selected) return;
        setState(() {
          _status = value;
          _items = _svc.pending(status: _status);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Role Approvals',
      onRefresh: _busy ? null : _reload,
      child: Column(
        children: [
          FTCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
              child: Wrap(
                spacing: AppTokens.s8,
                children: [
                  _statusChip('PENDING'),
                  _statusChip('APPROVED'),
                  _statusChip('REJECTED'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.s12),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _items,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return ListView(
                    children: const [
                      FTListCardSkeleton(withImage: false),
                      SizedBox(height: AppTokens.s12),
                      FTListCardSkeleton(withImage: false),
                    ],
                  );
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return FTEmptyState(
                    icon: Icons.verified_user_outlined,
                    title: 'No ${_status.toLowerCase()} approvals',
                    subtitle: 'Role requests will appear here as they are submitted.',
                    actionLabel: 'Refresh',
                    onAction: _reload,
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppTokens.s8),
                  itemBuilder: (_, i) {
                    final raw = items[i];
                    if (raw is! Map) return const SizedBox.shrink();
                    final item = Map<String, dynamic>.from(raw);
                    final requestedRole = (item['requested_role'] ?? '').toString();
                    final currentRole = (item['current_role'] ?? '').toString();
                    final status = (item['status'] ?? '').toString();
                    final reason = (item['reason'] ?? '').toString();
                    final createdAt = (item['created_at'] ?? '').toString();
                    final userId = (item['user_id'] ?? '').toString();

                    return FTCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FTTile(
                            title: 'User #$userId - $requestedRole',
                            subtitle:
                                'Current: $currentRole\nStatus: $status\n$createdAt${reason.isNotEmpty ? '\nReason: $reason' : ''}',
                            trailing: FTBadge(text: status.toUpperCase()),
                          ),
                          if (_status == 'PENDING') ...[
                            const SizedBox(height: AppTokens.s8),
                            Row(
                              children: [
                                Expanded(
                                  child: FTButton(
                                    label: 'Reject',
                                    variant: FTButtonVariant.destructive,
                                    onPressed: _busy ? null : () => _reject(item),
                                  ),
                                ),
                                const SizedBox(width: AppTokens.s8),
                                Expanded(
                                  child: FTButton(
                                    label: 'Approve',
                                    variant: FTButtonVariant.primary,
                                    onPressed: _busy ? null : () => _approve(item),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
