import 'package:flutter/material.dart';

import '../services/payment_service.dart';
import '../services/shortlet_service.dart';
import '../utils/formatters.dart';
import '../ui/components/ft_components.dart';
import '../widgets/safe_image.dart';

class ShortletDetailScreen extends StatefulWidget {
  const ShortletDetailScreen({super.key, required this.shortlet});

  final Map<String, dynamic> shortlet;

  @override
  State<ShortletDetailScreen> createState() => _ShortletDetailScreenState();
}

class _ShortletDetailScreenState extends State<ShortletDetailScreen> {
  final ShortletService _svc = ShortletService();
  final PaymentService _payments = PaymentService();
  final TextEditingController _checkInCtrl = TextEditingController();
  final TextEditingController _checkOutCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _proofRefCtrl = TextEditingController();
  final TextEditingController _proofNoteCtrl = TextEditingController();

  bool _loading = false;
  bool _booking = false;
  bool _favoriteBusy = false;
  bool _favorite = false;
  bool _viewSent = false;
  String _paymentMethod = 'wallet';
  int? _paymentIntentId;
  Map<String, dynamic> _shortlet = const <String, dynamic>{};
  Map<String, dynamic>? _manualInstructions;

  @override
  void initState() {
    super.initState();
    _shortlet = Map<String, dynamic>.from(widget.shortlet);
    _favorite = _shortlet['is_favorite'] == true;
    _refresh();
    _recordView();
  }

  @override
  void dispose() {
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _proofRefCtrl.dispose();
    _proofNoteCtrl.dispose();
    super.dispose();
  }

  int _id() => int.tryParse('${_shortlet['id'] ?? 0}') ?? 0;

  String _location(Map<String, dynamic> row) {
    final city = (row['city'] ?? '').toString().trim();
    final state = (row['state'] ?? '').toString().trim();
    if (city.isEmpty && state.isEmpty) return 'Location not set';
    if (city.isEmpty) return state;
    if (state.isEmpty) return city;
    return '$city, $state';
  }

  Future<void> _refresh() async {
    final id = _id();
    if (id <= 0) return;
    setState(() => _loading = true);
    final data = await _svc.getShortlet(id);
    if (!mounted) return;
    if (data['ok'] == true && data['shortlet'] is Map) {
      setState(() {
        _shortlet = Map<String, dynamic>.from(data['shortlet'] as Map);
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _recordView() async {
    if (_viewSent) return;
    final id = _id();
    if (id <= 0) return;
    _viewSent = true;
    final payload = await _svc.recordView(id,
        sessionKey: 'mobile-${DateTime.now().millisecondsSinceEpoch}');
    if (!mounted) return;
    if (payload['ok'] == true) {
      setState(() {
        _shortlet['views_count'] = int.tryParse(
                '${payload['views_count'] ?? _shortlet['views_count'] ?? 0}') ??
            0;
        _shortlet['favorites_count'] = int.tryParse(
                '${payload['favorites_count'] ?? _shortlet['favorites_count'] ?? 0}') ??
            0;
        _shortlet['heat_level'] =
            (payload['heat_level'] ?? _shortlet['heat_level'] ?? '').toString();
      });
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final id = _id();
    if (id <= 0) return;
    setState(() => _favoriteBusy = true);
    final payload = _favorite
        ? await _svc.unfavoriteShortlet(id)
        : await _svc.favoriteShortlet(id);
    if (!mounted) return;
    setState(() => _favoriteBusy = false);
    if (payload['ok'] == true) {
      setState(() {
        _favorite = !_favorite;
        _shortlet['favorites_count'] = int.tryParse(
                '${payload['favorites_count'] ?? _shortlet['favorites_count'] ?? 0}') ??
            0;
        _shortlet['heat_level'] =
            (payload['heat_level'] ?? _shortlet['heat_level'] ?? '').toString();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text((payload['message'] ?? 'Could not update watchlist')
                .toString())),
      );
    }
  }

  Future<void> _submitManualProof() async {
    final intentId = _paymentIntentId;
    if (intentId == null || intentId <= 0) return;
    final res = await _payments.submitManualProof(
      paymentIntentId: intentId,
      bankTxnReference: _proofRefCtrl.text.trim(),
      note: _proofNoteCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (res['ok'] == true)
              ? 'Payment proof submitted. Awaiting confirmation.'
              : (res['message'] ?? res['error'] ?? 'Proof submission failed')
                  .toString(),
        ),
      ),
    );
  }

  Future<void> _book() async {
    final id = _id();
    if (id <= 0) return;
    final checkIn = _checkInCtrl.text.trim();
    final checkOut = _checkOutCtrl.text.trim();
    if (checkIn.isEmpty || checkOut.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter check-in and check-out dates.')),
      );
      return;
    }
    setState(() => _booking = true);
    final resp = await _svc.bookShortlet(
      shortletId: id,
      checkIn: checkIn,
      checkOut: checkOut,
      guestName: _nameCtrl.text.trim(),
      guestPhone: _phoneCtrl.text.trim(),
      guests: int.tryParse('${_shortlet['guests'] ?? 1}') ?? 1,
      paymentMethod: _paymentMethod,
    );
    if (!mounted) return;
    setState(() => _booking = false);
    if (resp['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text((resp['message'] ?? resp['error'] ?? 'Booking failed')
                .toString())),
      );
      return;
    }
    final mode = (resp['mode'] ?? _paymentMethod).toString().toLowerCase();
    if (mode == 'bank_transfer_manual' || mode == 'manual_company_account') {
      setState(() {
        _paymentIntentId = int.tryParse('${resp['payment_intent_id'] ?? 0}');
        _manualInstructions = (resp['manual_instructions'] is Map)
            ? Map<String, dynamic>.from(resp['manual_instructions'] as Map)
            : <String, dynamic>{};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Manual payment initialized. Transfer and submit proof.')),
      );
      return;
    }
    if (mode == 'paystack') {
      final url = (resp['authorization_url'] ?? '').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(url.isEmpty
                ? 'Paystack initialization complete.'
                : 'Paystack URL generated.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Booking confirmed.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (_shortlet['title'] ?? 'Shortlet').toString();
    final desc = (_shortlet['description'] ?? '').toString();
    final price = _shortlet['nightly_price'] ?? _shortlet['price'] ?? 0;
    final beds = int.tryParse('${_shortlet['beds'] ?? 1}') ?? 1;
    final baths = int.tryParse('${_shortlet['baths'] ?? 1}') ?? 1;
    final guests = int.tryParse('${_shortlet['guests'] ?? 1}') ?? 1;
    final views = int.tryParse('${_shortlet['views_count'] ?? 0}') ?? 0;
    final watching = int.tryParse('${_shortlet['favorites_count'] ?? 0}') ?? 0;
    final heat =
        (_shortlet['heat_level'] ?? '').toString().trim().toLowerCase();
    final mediaRows = (_shortlet['media'] is List)
        ? (_shortlet['media'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final fallbackImage =
        (_shortlet['image'] ?? _shortlet['image_url'] ?? '').toString();

    return FTScaffold(
      title: 'Shortlet Details',
      actions: [
        IconButton(
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [
          if (mediaRows.isNotEmpty)
            SizedBox(
              height: 240,
              child: PageView.builder(
                itemCount: mediaRows.length,
                itemBuilder: (_, index) {
                  final row = mediaRows[index];
                  final thumb =
                      (row['thumbnail_url'] ?? row['url'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SafeImage(
                        url: thumb,
                        width: double.infinity,
                        height: 240,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SafeImage(
                url: fallbackImage,
                width: double.infinity,
                height: 240,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: _favoriteBusy ? null : _toggleFavorite,
                icon: Icon(
                  _favorite ? Icons.favorite : Icons.favorite_border,
                  color: _favorite ? Colors.redAccent : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatNaira(price, decimals: 0),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(_location(_shortlet),
              style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FTPill(text: '$beds beds', bgColor: const Color(0xFFF1F5F9)),
              FTPill(text: '$baths baths', bgColor: const Color(0xFFF1F5F9)),
              FTPill(text: '$guests guests', bgColor: const Color(0xFFF1F5F9)),
              FTPill(text: '$views views', bgColor: const Color(0xFFF1F5F9)),
              FTPill(
                  text: '$watching watching', bgColor: const Color(0xFFFFF1F2)),
              if (heat == 'hot' || heat == 'hotter')
                FTPill(
                  text: heat == 'hotter' ? 'Hotter' : 'Hot',
                  bgColor: heat == 'hotter'
                      ? const Color(0xFFFFEDD5)
                      : const Color(0xFFFEF3C7),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FTSectionContainer(
            title: 'About',
            child: Text(
              desc.trim().isEmpty ? 'No description provided.' : desc,
            ),
          ),
          const SizedBox(height: 12),
          FTSectionContainer(
            title: 'Book this shortlet',
            child: Column(
              children: [
                TextField(
                  controller: _checkInCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Check-in (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _checkOutCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Check-out (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Guest name (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Guest phone (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  items: const [
                    DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
                    DropdownMenuItem(
                        value: 'paystack', child: Text('Paystack (Card/Bank)')),
                    DropdownMenuItem(
                        value: 'bank_transfer_manual',
                        child: Text('Bank Transfer (Manual)')),
                  ],
                  onChanged: (value) {
                    if (value == null || value.trim().isEmpty) return;
                    setState(() => _paymentMethod = value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _booking ? null : _book,
                    icon: const Icon(Icons.lock_outline),
                    label: Text(_booking ? 'Processing...' : 'Book now'),
                  ),
                ),
              ],
            ),
          ),
          if (_manualInstructions != null) ...[
            const SizedBox(height: 12),
            FTSectionContainer(
              title: 'Manual payment instructions',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Bank: ${(_manualInstructions!['bank_name'] ?? '').toString()}'),
                  Text(
                      'Account name: ${(_manualInstructions!['account_name'] ?? '').toString()}'),
                  Text(
                      'Account number: ${(_manualInstructions!['account_number'] ?? '').toString()}'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _proofRefCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bank transaction reference',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _proofNoteCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _submitManualProof,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Submit payment proof'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
