import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/merchant_service.dart';

class MerchantDetailScreen extends StatefulWidget {
  const MerchantDetailScreen({super.key, required this.userId});

  final int userId;

  @override
  State<MerchantDetailScreen> createState() => _MerchantDetailScreenState();
}

class _MerchantDetailScreenState extends State<MerchantDetailScreen> {
  final _svc = MerchantService();
  final _auth = AuthService();
  late Future<Map<String, dynamic>> _future;

  final _reviewCtrl = TextEditingController();
  int _rating = 5;
  bool _followBusy = false;
  String _viewerRole = 'buyer';
  int? _viewerId;

  @override
  void initState() {
    super.initState();
    _future = _svc.merchantDetail(widget.userId);
    _loadProfile();
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = _svc.merchantDetail(widget.userId));
  }

  Future<void> _loadProfile() async {
    final profile = await _auth.me();
    if (!mounted) return;
    setState(() {
      _viewerRole = (profile?['role'] ?? 'buyer').toString();
      final idVal = profile?['id'];
      _viewerId = idVal is int ? idVal : int.tryParse(idVal?.toString() ?? '');
    });
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Merchant')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snap.data ?? {};
            final ok = data['ok'] == true;
            if (!ok) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Merchant not found.')),
                ],
              );
            }

            final merchant = (data['merchant'] is Map)
                ? Map<String, dynamic>.from(data['merchant'] as Map)
                : <String, dynamic>{};
            final reviews = (data['reviews'] is List)
                ? (data['reviews'] as List)
                : <dynamic>[];

            final name = (merchant['shop_name'] ?? '').toString().trim().isEmpty
                ? 'Merchant ${merchant['user_id']}'
                : (merchant['shop_name'] ?? '').toString();
            final badge = (merchant['badge'] ?? 'New').toString();
            final location = [merchant['city'], merchant['state']]
                .where((value) => (value ?? '').toString().trim().isNotEmpty)
                .join(', ');
            final followers = (merchant['followers'] ?? 0).toString();
            final isFollowing = merchant['is_following'] == true;
            final canFollow = _viewerRole.toLowerCase() == 'buyer' &&
                (_viewerId ?? 0) != (merchant['user_id'] ?? -1);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          location,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _metric('Badge', badge),
                            const SizedBox(width: 10),
                            _metric('Score', (merchant['score'] ?? 0).toString()),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _metric('Orders',
                                (merchant['total_orders'] ?? 0).toString()),
                            const SizedBox(width: 10),
                            _metric(
                              'Sales',
                              'NGN ${(merchant['total_sales'] ?? 0)}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _metric('Rating',
                                (merchant['avg_rating'] ?? 0).toString()),
                            const SizedBox(width: 10),
                            _metric('Ratings',
                                (merchant['rating_count'] ?? 0).toString()),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(children: [_metric('Followers', followers)]),
                        if (canFollow) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 46,
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _followBusy
                                  ? null
                                  : () async {
                                      setState(() => _followBusy = true);
                                      if (isFollowing) {
                                        await _svc.unfollowMerchant(widget.userId);
                                      } else {
                                        await _svc.followMerchant(widget.userId);
                                      }
                                      if (!context.mounted) return;
                                      setState(() => _followBusy = false);
                                      _reload();
                                    },
                              icon: Icon(isFollowing
                                  ? Icons.check_circle_outline
                                  : Icons.person_add_alt_1),
                              label: Text(isFollowing ? 'Following' : 'Follow'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Leave a review',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<int>(
                          initialValue: _rating,
                          decoration: const InputDecoration(
                            labelText: 'Rating',
                            border: OutlineInputBorder(),
                          ),
                          items: const [5, 4, 3, 2, 1]
                              .map((value) => DropdownMenuItem(
                                  value: value, child: Text('$value stars')))
                              .toList(growable: false),
                          onChanged: (value) => setState(() => _rating = value ?? 5),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _reviewCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Comment',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final res = await _svc.addReview(
                                userId: widget.userId,
                                rating: _rating,
                                comment: _reviewCtrl.text.trim(),
                              );
                              final okReview = res['ok'] == true;
                              if (!context.mounted) return;
                              if (okReview) {
                                _reviewCtrl.clear();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Review added.')),
                                );
                                _reload();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Review failed.')),
                                );
                              }
                            },
                            icon: const Icon(Icons.rate_review_outlined),
                            label: const Text('Submit review'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Recent reviews',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (reviews.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No reviews yet.'),
                    ),
                  )
                else
                  ...reviews.whereType<Map>().map((raw) {
                    final review = Map<String, dynamic>.from(raw);
                    final rater = (review['rater_name'] ?? 'Anonymous').toString();
                    final rating = (review['rating'] ?? 0).toString();
                    final comment = (review['comment'] ?? '').toString();
                    return Card(
                      child: ListTile(
                        title: Text(
                          '$rater | $rating stars',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(comment),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}

