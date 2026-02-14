import 'package:flutter/material.dart';
import '../services/shortlet_service.dart';
import '../widgets/safe_image.dart';

class ShortletDetailsScreen extends StatefulWidget {
  const ShortletDetailsScreen({super.key, required this.shortlet});

  final Map<String, dynamic> shortlet;

  @override
  State<ShortletDetailsScreen> createState() => _ShortletDetailsScreenState();
}

class _ShortletDetailsScreenState extends State<ShortletDetailsScreen> {
  final _svc = ShortletService();

  final _checkInCtrl = TextEditingController();
  final _checkOutCtrl = TextEditingController();
  final _guestNameCtrl = TextEditingController();
  final _guestPhoneCtrl = TextEditingController();
  final _ratingCtrl = TextEditingController(text: "5");

  bool _loading = false;

  @override
  void dispose() {
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    _guestNameCtrl.dispose();
    _guestPhoneCtrl.dispose();
    _ratingCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.shortlet;
    final title = (s['title'] ?? '').toString();
    final img = (s['image'] ?? '').toString();
    final price = (s['nightly_price'] ?? 0).toString();
    final cleaning = (s['cleaning_fee'] ?? 0).toString();
    final rating = (s['rating'] ?? 0).toString();
    final reviews = (s['reviews_count'] ?? 0).toString();

    final loc = [
      s['locality'],
      s['city'],
      s['state'],
    ].where((x) => (x ?? '').toString().trim().isNotEmpty).join(", ");

    final amenities = (s['amenities'] is List)
        ? (s['amenities'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final rules = (s['house_rules'] is List)
        ? (s['house_rules'] as List).map((e) => e.toString()).toList()
        : <String>[];

    return Scaffold(
      appBar: AppBar(title: const Text("Shortlet Details")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SafeImage(url: img, height: 220, width: double.infinity),
          ),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          Text(loc, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text("₦$price / night",
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Text("Cleaning: ₦$cleaning",
                  style: TextStyle(color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 8),
          Text("★ $rating ($reviews reviews)",
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const Divider(height: 24),
          if (amenities.isNotEmpty) ...[
            const Text("Amenities",
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  amenities.take(18).map((a) => Chip(label: Text(a))).toList(),
            ),
            const Divider(height: 24),
          ],
          if (rules.isNotEmpty) ...[
            const Text("House Rules",
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...rules.take(10).map((x) =>
                ListTile(leading: const Icon(Icons.rule), title: Text(x))),
            const Divider(height: 24),
          ],
          const Text("Book this Shortlet (MVP)",
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TextField(
              controller: _checkInCtrl,
              decoration: const InputDecoration(
                  labelText: "Check-in (YYYY-MM-DD)",
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: _checkOutCtrl,
              decoration: const InputDecoration(
                  labelText: "Check-out (YYYY-MM-DD)",
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: _guestNameCtrl,
              decoration: const InputDecoration(
                  labelText: "Guest name (optional)",
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: _guestPhoneCtrl,
              decoration: const InputDecoration(
                  labelText: "Phone (optional)", border: OutlineInputBorder())),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _loading
                  ? null
                  : () async {
                      final id = int.tryParse((s['id'] ?? 0).toString()) ?? 0;
                      if (id <= 0) return;

                      setState(() => _loading = true);

                      final res = await _svc.bookShortlet(
                        shortletId: id,
                        checkIn: _checkInCtrl.text.trim(),
                        checkOut: _checkOutCtrl.text.trim(),
                        guestName: _guestNameCtrl.text.trim(),
                        guestPhone: _guestPhoneCtrl.text.trim(),
                      );

                      if (!context.mounted) return;
                      setState(() => _loading = false);

                      final ok = res['ok'] == true;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                ok ? "Booking requested." : "Booking failed.")),
                      );
                    },
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text("Request Booking"),
            ),
          ),
          const Divider(height: 24),
          const Text("Leave a Review (MVP)",
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TextField(
              controller: _ratingCtrl,
              decoration: const InputDecoration(
                  labelText: "Rating 0 - 5", border: OutlineInputBorder())),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () async {
                      final id = int.tryParse((s['id'] ?? 0).toString()) ?? 0;
                      if (id <= 0) return;

                      setState(() => _loading = true);
                      var ok = false;
                      try {
                        final rating =
                            double.tryParse(_ratingCtrl.text.trim()) ?? 5;
                        ok = await _svc.submitReview(
                            shortletId: id, rating: rating);
                      } catch (_) {}
                      if (!context.mounted) return;
                      setState(() => _loading = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              ok ? "Review submitted." : "Review failed.")));
                    },
              icon: const Icon(Icons.star_rate_outlined),
              label: const Text("Submit rating"),
            ),
          ),
        ],
      ),
    );
  }
}
