import 'package:flutter/material.dart';

class MarketplaceFiltersScreen extends StatefulWidget {
  final List<String> categories;
  final String selectedCategory;
  final String initialQuery;
  final double? initialMinPrice;
  final double? initialMaxPrice;

  const MarketplaceFiltersScreen({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.initialQuery,
    this.initialMinPrice,
    this.initialMaxPrice,
  });

  @override
  State<MarketplaceFiltersScreen> createState() => _MarketplaceFiltersScreenState();
}

class _MarketplaceFiltersScreenState extends State<MarketplaceFiltersScreen> {
  late final TextEditingController _queryCtrl;
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late String _category;

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.initialQuery);
    _minCtrl = TextEditingController(
      text: widget.initialMinPrice == null ? '' : widget.initialMinPrice!.toStringAsFixed(0),
    );
    _maxCtrl = TextEditingController(
      text: widget.initialMaxPrice == null ? '' : widget.initialMaxPrice!.toStringAsFixed(0),
    );
    _category = widget.selectedCategory;
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  double? _toDouble(String value) {
    final t = value.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  void _apply() {
    final minPrice = _toDouble(_minCtrl.text);
    final maxPrice = _toDouble(_maxCtrl.text);
    if (minPrice != null && maxPrice != null && minPrice > maxPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Min price cannot be greater than max price.')),
      );
      return;
    }
    Navigator.pop(context, {
      'query': _queryCtrl.text.trim(),
      'category': _category,
      'minPrice': minPrice,
      'maxPrice': maxPrice,
    });
  }

  void _clear() {
    setState(() {
      _queryCtrl.clear();
      _minCtrl.clear();
      _maxCtrl.clear();
      _category = 'All';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marketplace Filters')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _queryCtrl,
            decoration: const InputDecoration(
              labelText: 'Search text',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _category,
            items: widget.categories
                .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
                .toList(),
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _category = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Min price',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Max price',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clear,
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _apply,
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
