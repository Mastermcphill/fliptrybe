import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/referral_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';

class InviteEarnScreen extends StatefulWidget {
  const InviteEarnScreen({super.key});

  @override
  State<InviteEarnScreen> createState() => _InviteEarnScreenState();
}

class _InviteEarnScreenState extends State<InviteEarnScreen> {
  final ReferralService _service = ReferralService();
  bool _loading = true;
  String? _error;
  String _code = '';
  Map<String, dynamic> _stats = const <String, dynamic>{};
  List<Map<String, dynamic>> _history = const <Map<String, dynamic>>[];

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
      final stats = await _service.stats();
      final code = (stats['referral_code'] ?? '').toString().trim();
      final historyRes = await _service.history(limit: 20);
      final rawItems = historyRes['items'];
      final items = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _code = code;
        _stats = stats;
        _history = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UIFeedback.mapDioErrorToMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _copyCode() async {
    final code = _code.trim();
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    UIFeedback.showSuccessSnack(context, 'Referral code copied.');
  }

  Future<void> _shareText() async {
    final code = _code.trim();
    if (code.isEmpty) return;
    final text =
        'Join FlipTrybe with my referral code: $code. Browse deals, shortlets and earn more.';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    UIFeedback.showSuccessSnack(
        context, 'Invite text copied. Share it anywhere.');
  }

  @override
  Widget build(BuildContext context) {
    final earnedMinor = int.tryParse('${_stats['earned_minor'] ?? 0}') ?? 0;
    final joined = int.tryParse('${_stats['joined'] ?? 0}') ?? 0;
    final completed = int.tryParse('${_stats['completed'] ?? 0}') ?? 0;
    return FTScaffold(
      title: 'Invite & Earn',
      onRefresh: _load,
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: false,
        loadingState: FTSkeletonList(
          itemCount: 4,
          itemBuilder: (_, __) => const FTSkeletonCard(height: 90),
        ),
        emptyState: const SizedBox.shrink(),
        child: ListView(
          children: [
            FTSection(
              title: 'Your referral code',
              subtitle:
                  'Share this code. Reward unlocks after first successful transaction.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FTCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _code.isEmpty ? 'Generating...' : _code,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        FTButton(
                          label: 'Copy',
                          icon: Icons.copy_outlined,
                          variant: FTButtonVariant.ghost,
                          onPressed: _code.isEmpty ? null : _copyCode,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  FTAsyncButton(
                    label: 'Share invite text',
                    icon: Icons.ios_share_outlined,
                    onPressed: _shareText,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Referral stats',
              child: Column(
                children: [
                  FTMetricTile(label: 'Joined', value: '$joined'),
                  const SizedBox(height: 8),
                  FTMetricTile(label: 'Completed', value: '$completed'),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Earned',
                    value: formatNaira(earnedMinor / 100),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'History',
              subtitle: 'Latest referrals and reward status.',
              child: _history.isEmpty
                  ? FTEmptyState(
                      icon: Icons.group_add_outlined,
                      title: 'No referrals yet',
                      subtitle: 'Share your code and track conversions here.',
                      primaryCtaText: 'Refresh',
                      onPrimaryCta: _load,
                    )
                  : Column(
                      children: _history.map((item) {
                        final referred = item['referred_user'];
                        final referredMap = referred is Map
                            ? Map<String, dynamic>.from(referred)
                            : const <String, dynamic>{};
                        final name =
                            (referredMap['name'] ?? '').toString().trim();
                        final email =
                            (referredMap['email'] ?? '').toString().trim();
                        final status = (item['status'] ?? 'pending').toString();
                        final rewardMinor = int.tryParse(
                                '${item['reward_amount_minor'] ?? 0}') ??
                            0;
                        return FTListTile(
                          leading: const Icon(Icons.person_add_alt_1_outlined),
                          title: name.isNotEmpty ? name : email,
                          subtitle:
                              '${status.toUpperCase()} - ${formatNaira(rewardMinor / 100)}',
                          badgeText: status.toLowerCase() == 'completed'
                              ? 'Paid'
                              : 'Pending',
                          onTap: null,
                        );
                      }).toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
