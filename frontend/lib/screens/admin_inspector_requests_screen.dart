import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../ui/admin/admin_scaffold.dart';
import '../ui/components/ft_components.dart';
import '../ui/foundation/app_tokens.dart';

class AdminInspectorRequestsScreen extends StatefulWidget {
  const AdminInspectorRequestsScreen({super.key});

  @override
  State<AdminInspectorRequestsScreen> createState() =>
      _AdminInspectorRequestsScreenState();
}

class _AdminInspectorRequestsScreenState
    extends State<AdminInspectorRequestsScreen> {
  bool _loading = false;
  String? _error;
  List<dynamic> _items = const [];
  String _status = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.dio
          .get(ApiConfig.api('/admin/inspector-requests?status=$_status'));
      final data = res.data;
      final items = (data is Map && data['items'] is List)
          ? (data['items'] as List)
          : <dynamic>[];
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(int reqId) async {
    try {
      final res = await ApiClient.instance.dio
          .post(ApiConfig.api('/admin/inspector-requests/$reqId/approve'));
      if (res.statusCode != null &&
          res.statusCode! >= 200 &&
          res.statusCode! < 300) {
        final data = res.data;
        final created = (data is Map && data['created'] != null)
            ? data['created'].toString()
            : '';
        final user =
            (data is Map && data['user'] is Map) ? data['user'] as Map : null;
        final userId = user != null ? user['id'] : null;
        if (!mounted) return;
        final msg = userId != null
            ? 'Approved as user #$userId (created: $created)'
            : 'Approved';
        FTToast.show(context, msg);
        _load();
      } else {
        if (!mounted) return;
        FTToast.show(context, 'Approve failed');
      }
    } catch (e) {
      if (!mounted) return;
      FTToast.show(context, 'Approve failed: $e');
    }
  }

  Future<void> _reject(int reqId) async {
    try {
      final res = await ApiClient.instance.dio
          .post(ApiConfig.api('/admin/inspector-requests/$reqId/reject'));
      if (res.statusCode != null &&
          res.statusCode! >= 200 &&
          res.statusCode! < 300) {
        _load();
      } else {
        if (!mounted) return;
        FTToast.show(context, 'Reject failed');
      }
    } catch (e) {
      if (!mounted) return;
      FTToast.show(context, 'Reject failed: $e');
    }
  }

  Widget _filterChip(String value, String label) {
    final selected = _status == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        if (!v) return;
        setState(() => _status = value);
        _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Inspector Requests',
      onRefresh: _load,
      child: Column(
        children: [
          FTCard(
            child: Wrap(
              spacing: AppTokens.s8,
              children: [
                _filterChip('pending', 'Pending'),
                _filterChip('approved', 'Approved'),
                _filterChip('rejected', 'Rejected'),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.s12),
          Expanded(
            child: FTLoadStateLayout(
              loading: _loading,
              error: _error,
              onRetry: _load,
              empty: _items.isEmpty,
              loadingState: ListView(
                children: const [
                  FTListCardSkeleton(withImage: false),
                  SizedBox(height: AppTokens.s12),
                  FTListCardSkeleton(withImage: false),
                ],
              ),
              emptyState: FTEmptyState(
                icon: Icons.assignment_ind_outlined,
                title: 'No inspector requests',
                subtitle: 'Requests with selected status will appear here.',
                actionLabel: 'Refresh',
                onAction: _load,
              ),
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppTokens.s8),
                itemBuilder: (context, i) {
                  final raw = _items[i];
                  if (raw is! Map) return const SizedBox.shrink();
                  final m = Map<String, dynamic>.from(raw);
                  final id = m['id'];
                  final name = (m['name'] ?? '').toString();
                  final email = (m['email'] ?? '').toString();
                  final phone = (m['phone'] ?? '').toString();
                  final notes = (m['notes'] ?? '').toString();
                  final status = (m['status'] ?? '').toString();
                  final decidedBy = (m['decided_by'] ?? '').toString();
                  return FTCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FTTile(
                          title: name.isEmpty ? email : name,
                          subtitle:
                              '$email\n$phone\n$notes\nstatus: $status${decidedBy.isNotEmpty ? ' - decided_by: $decidedBy' : ''}',
                          trailing: FTBadge(text: status.toUpperCase()),
                        ),
                        if (_status == 'pending') ...[
                          const SizedBox(height: AppTokens.s8),
                          Row(
                            children: [
                              Expanded(
                                child: FTButton(
                                  label: 'Approve',
                                  icon: Icons.check_circle_outline,
                                  onPressed: () {
                                    final reqId = id is int
                                        ? id
                                        : int.tryParse(id?.toString() ?? '');
                                    if (reqId != null) _approve(reqId);
                                  },
                                ),
                              ),
                              const SizedBox(width: AppTokens.s8),
                              Expanded(
                                child: FTButton(
                                  label: 'Reject',
                                  variant: FTButtonVariant.destructive,
                                  icon: Icons.cancel_outlined,
                                  onPressed: () {
                                    final reqId = id is int
                                        ? id
                                        : int.tryParse(id?.toString() ?? '');
                                    if (reqId != null) _reject(reqId);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
