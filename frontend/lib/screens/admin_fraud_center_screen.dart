import 'package:flutter/material.dart';

import '../services/omega_intelligence_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/ui_feedback.dart';

class AdminFraudCenterScreen extends StatefulWidget {
  const AdminFraudCenterScreen({
    super.key,
    this.service,
    this.autoLoad = true,
    this.initialFlags,
  });

  final OmegaIntelligenceService? service;
  final bool autoLoad;
  final List<Map<String, dynamic>>? initialFlags;

  @override
  State<AdminFraudCenterScreen> createState() => _AdminFraudCenterScreenState();
}

class _AdminFraudCenterScreenState extends State<AdminFraudCenterScreen> {
  late final OmegaIntelligenceService _svc;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  int _minScore = 30;
  List<Map<String, dynamic>> _flags = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? OmegaIntelligenceService();
    if (widget.initialFlags != null) {
      _flags = List<Map<String, dynamic>>.from(widget.initialFlags!);
      _loading = false;
      return;
    }
    if (widget.autoLoad) {
      _load(refresh: true);
    } else {
      _loading = false;
    }
  }

  Future<void> _load({required bool refresh}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      if (_flags.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final items = await _svc.fraudFlags(
        refresh: refresh,
        status: 'open_only',
        minScore: _minScore,
      );
      if (!mounted) return;
      setState(() => _flags = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = UIFeedback.mapDioErrorToMessage(e));
      UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _markReviewed(int fraudFlagId) async {
    try {
      await _svc.reviewFraudFlag(
        fraudFlagId: fraudFlagId,
        status: 'reviewed',
        note: 'Reviewed in Fraud Center.',
      );
      if (!mounted) return;
      UIFeedback.showSuccessSnack(context, 'Flag marked as reviewed.');
      await _load(refresh: false);
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
    }
  }

  Future<void> _freeze(int fraudFlagId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Freeze account'),
        content: const Text(
          'This will mark the fraud case as action taken and freeze the account where supported. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Freeze'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _svc.freezeFraudFlag(
        fraudFlagId: fraudFlagId,
        note: 'Actioned from Fraud Center.',
      );
      if (!mounted) return;
      UIFeedback.showSuccessSnack(context, 'Freeze action submitted.');
      await _load(refresh: false);
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
    }
  }

  Widget _flagCard(Map<String, dynamic> row) {
    final user = (row['user'] is Map)
        ? Map<String, dynamic>.from(row['user'] as Map)
        : <String, dynamic>{};
    final reasonsWrap = (row['reasons'] is Map)
        ? Map<String, dynamic>.from(row['reasons'] as Map)
        : <String, dynamic>{};
    final reasonsList = (reasonsWrap['items'] is List)
        ? List<dynamic>.from(reasonsWrap['items'] as List)
        : const <dynamic>[];
    final score = (row['score'] as num?)?.toInt() ?? 0;
    final level = (row['level'] ?? 'normal').toString().toUpperCase();
    final flagId = (row['id'] as num?)?.toInt() ?? 0;
    final status = (row['status'] ?? '').toString();

    return FTCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FTResponsiveTitleAction(
            title:
                '${user['name'] ?? 'User #${user['id'] ?? row['user_id'] ?? ''}'}',
            subtitle: (user['email'] ?? '').toString(),
            action: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Score $score',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Level: $level'),
          Text('Status: ${status.toUpperCase()}'),
          const SizedBox(height: 8),
          if (reasonsList.isEmpty)
            const Text('No trigger breakdown available.')
          else
            ...reasonsList.take(4).map((entry) {
              if (entry is Map) {
                final code = (entry['code'] ?? '').toString();
                final weight = (entry['weight'] ?? '').toString();
                return Text('- $code  (weight $weight)');
              }
              return Text('- ${entry.toString()}');
            }),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FTButton(
                  label: 'Mark reviewed',
                  variant: FTButtonVariant.ghost,
                  onPressed: flagId > 0 ? () => _markReviewed(flagId) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FTButton(
                  label: 'Freeze account',
                  variant: FTButtonVariant.destructive,
                  onPressed: flagId > 0 ? () => _freeze(flagId) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Fraud Center',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _refreshing ? null : () => _load(refresh: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: () => _load(refresh: true),
        loadingState: const FTSkeletonList(
          itemCount: 5,
          itemBuilder: _skeletonItem,
        ),
        empty: !_loading && _flags.isEmpty,
        emptyState: FTEmptyState(
          icon: Icons.shield_outlined,
          title: 'No high-risk flags',
          subtitle: 'No fraud flags above current threshold.',
          primaryCtaText: 'Refresh',
          onPrimaryCta: () => _load(refresh: true),
        ),
        child: ListView(
          children: [
            FTCard(
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _minScore,
                      decoration: const InputDecoration(
                        labelText: 'Minimum score',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 30, child: Text('30+ Monitor')),
                        DropdownMenuItem(value: 60, child: Text('60+ Flag')),
                        DropdownMenuItem(value: 80, child: Text('80+ Freeze')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _minScore = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  FTButton(
                    label: 'Apply',
                    onPressed: _refreshing ? null : () => _load(refresh: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ..._flags.map(_flagCard),
          ],
        ),
      ),
    );
  }
}

Widget _skeletonItem(BuildContext context, int _) {
  return const Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: FTSkeletonCard(height: 120),
  );
}
