import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';

class FeesDemoScreen extends StatefulWidget {
  const FeesDemoScreen({super.key});

  @override
  State<FeesDemoScreen> createState() => _FeesDemoScreenState();
}

class _FeesDemoScreenState extends State<FeesDemoScreen> {
  final _amountCtrl = TextEditingController(text: "10000");
  String _kind = "listing_sale";
  Map<String, dynamic>? _result;
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _quote() async {
    setState(() {
      _loading = true;
      _result = null;
    });

    final amount = _amountCtrl.text.trim();
    final url = ApiConfig.api('/fees/quote') +
        '?kind=${Uri.encodeComponent(_kind)}&amount=${Uri.encodeComponent(amount)}';

    try {
      final data = await ApiClient.instance.getJson(url);
      if (!mounted) return;
      setState(() {
        _result = Map<String, dynamic>.from(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = {"ok": false, "error": e.toString()};
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Fees & Commission (Demo)")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Commission engine (MVP)",
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: const InputDecoration(
                labelText: "Fee type", border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(
                  value: "listing_sale",
                  child: Text("Listing sale commission")),
              DropdownMenuItem(
                  value: "delivery", child: Text("Delivery commission")),
              DropdownMenuItem(
                  value: "withdrawal", child: Text("Withdrawal commission")),
              DropdownMenuItem(
                  value: "shortlet_booking",
                  child: Text("Shortlet booking commission")),
            ],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
                labelText: "Amount (₦)", border: OutlineInputBorder()),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _quote,
              icon: const Icon(Icons.calculate_outlined),
              label: Text(_loading ? "..." : "Get quote"),
            ),
          ),
          const SizedBox(height: 12),
          if (_result != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        "Rate: ${(100 * (_result!['rate'] ?? 0)).toString()}%"),
                    Text("Fee: ₦${_result!['fee'] ?? '-'}"),
                    Text("Total: ₦${_result!['total'] ?? '-'}",
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            )
          ]
        ],
      ),
    );
  }
}
