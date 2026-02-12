import 'package:flutter/material.dart';

import '../../widgets/growth/moneybox_projection_table.dart';
import '../../widgets/growth/projection_table.dart';

class RoleGrowthCalculator extends StatefulWidget {
  const RoleGrowthCalculator({
    super.key,
    required this.role,
  });

  final String role;

  @override
  State<RoleGrowthCalculator> createState() => _RoleGrowthCalculatorState();
}

class _RoleGrowthCalculatorState extends State<RoleGrowthCalculator> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController(text: '5000');
  final _countCtrl = TextEditingController(text: '4');
  final _daysCtrl = TextEditingController(text: '26');
  final _platformRateCtrl = TextEditingController(text: '3');
  final _autosaveCtrl = TextEditingController(text: '10');

  bool _isTopTier = false;
  String _withdrawalSpeed = 'standard';
  Map<String, double>? _result;
  List<Map<String, double>> _projectionRows = const [];
  List<Map<String, double>> _moneyBoxRows = const [];
  String _validationMessage = '';

  @override
  void dispose() {
    _amountCtrl.dispose();
    _countCtrl.dispose();
    _daysCtrl.dispose();
    _platformRateCtrl.dispose();
    _autosaveCtrl.dispose();
    super.dispose();
  }

  bool get _isMerchant => widget.role.toLowerCase() == 'merchant';
  bool get _isDriver => widget.role.toLowerCase() == 'driver';
  bool get _isInspector => widget.role.toLowerCase() == 'inspector';

  String _money(num value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final chars = parts[0].split('').reversed.toList();
    final out = <String>[];
    for (int i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) out.add(',');
      out.add(chars[i]);
    }
    final grouped = out.reversed.join();
    return '?$grouped.${parts[1]}';
  }

  String _amountLabel() {
    if (_isMerchant) return 'Avg item price (?)';
    if (_isDriver) return 'Avg delivery fee (?)';
    return 'Avg inspection fee (?)';
  }

  String _countLabel() {
    if (_isMerchant) return 'Orders per day';
    if (_isDriver) return 'Deliveries per day';
    return 'Inspections per day';
  }

  void _calculate() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountCtrl.text.trim());
    final count = double.parse(_countCtrl.text.trim());
    final days = double.parse(_daysCtrl.text.trim());
    final platformRate =
        _isMerchant ? double.parse(_platformRateCtrl.text.trim()) / 100 : 0.10;
    final autosavePct = double.parse(_autosaveCtrl.text.trim()) / 100;

    final dailyGross = amount * count;
    final weeklyGross = dailyGross * 7;
    final monthlyGross = dailyGross * days;
    final yearlyGross = monthlyGross * 12;

    final dailyCommission = dailyGross * platformRate;
    final weeklyCommission = weeklyGross * platformRate;
    final monthlyCommission = monthlyGross * platformRate;
    final yearlyCommission = yearlyGross * platformRate;

    final incentiveRate = _isMerchant && _isTopTier ? (11.0 / 13.0) : 0.0;
    final monthlyIncentive = monthlyCommission * incentiveRate;

    double monthlyNet;
    if (_isMerchant) {
      monthlyNet = monthlyGross + monthlyIncentive;
    } else {
      monthlyNet = monthlyGross - monthlyCommission;
    }

    final withdrawalRate =
        (_isDriver || _isInspector) && _withdrawalSpeed == 'instant'
            ? 0.01
            : 0.0;
    final monthlyWithdrawalFee = monthlyNet * withdrawalRate;
    final monthlyTakeHome = monthlyNet - monthlyWithdrawalFee;

    final daysFactor = days / 30.0;
    final dailyNet = monthlyNet / days;
    final weeklyNet = dailyNet * 7;
    final yearlyNet = monthlyNet * 12;

    final dailyTakeHome = monthlyTakeHome / days;
    final weeklyTakeHome = dailyTakeHome * 7;
    final yearlyTakeHome = monthlyTakeHome * 12;

    final dailyWithdrawalFee = dailyTakeHome * withdrawalRate;
    final weeklyWithdrawalFee = weeklyTakeHome * withdrawalRate;
    final yearlyWithdrawalFee = yearlyTakeHome * withdrawalRate;

    final monthlyAutosave = monthlyTakeHome * autosavePct;

    final tiers = <Map<String, double>>[
      {'tier': 1, 'days': 30, 'bonusPct': 0},
      {'tier': 2, 'days': 120, 'bonusPct': 3},
      {'tier': 3, 'days': 210, 'bonusPct': 8},
      {'tier': 4, 'days': 330, 'bonusPct': 15},
    ];

    final moneyRows = tiers.map((tier) {
      final d = tier['days']!;
      final mths = d / 30;
      final principal = monthlyAutosave * mths;
      final bonus = principal * (tier['bonusPct']! / 100);
      return {
        'tier': tier['tier']!,
        'days': d,
        'bonusPct': tier['bonusPct']!,
        'principal': principal,
        'bonus': bonus,
        'maturity': principal + bonus,
      };
    }).toList();

    setState(() {
      _validationMessage = '';
      _result = {
        'monthlyGross': monthlyGross,
        'monthlyCommission': monthlyCommission,
        'monthlyIncentive': monthlyIncentive,
        'monthlyNet': monthlyNet,
        'monthlyWithdrawalFee': monthlyWithdrawalFee,
        'monthlyTakeHome': monthlyTakeHome,
        'monthlyAutosave': monthlyAutosave,
        'daysFactor': daysFactor,
      };
      _projectionRows = [
        {
          'labelIndex': 0,
          'gross': dailyGross,
          'commission': dailyCommission,
          'net': dailyNet,
          'withdrawalFee': dailyWithdrawalFee,
          'takeHome': dailyTakeHome,
        },
        {
          'labelIndex': 1,
          'gross': weeklyGross,
          'commission': weeklyCommission,
          'net': weeklyNet,
          'withdrawalFee': weeklyWithdrawalFee,
          'takeHome': weeklyTakeHome,
        },
        {
          'labelIndex': 2,
          'gross': monthlyGross,
          'commission': monthlyCommission,
          'net': monthlyNet,
          'withdrawalFee': monthlyWithdrawalFee,
          'takeHome': monthlyTakeHome,
        },
        {
          'labelIndex': 3,
          'gross': yearlyGross,
          'commission': yearlyCommission,
          'net': yearlyNet,
          'withdrawalFee': yearlyWithdrawalFee,
          'takeHome': yearlyTakeHome,
        },
      ];
      _moneyBoxRows = moneyRows;
    });
  }

  String? _validatePositive(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Required';
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) return 'Enter value > 0';
    return null;
  }

  String? _validateAutosave(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Required';
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1 || parsed > 30) {
      return 'Enter 1 to 30';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel =
        widget.role[0].toUpperCase() + widget.role.substring(1).toLowerCase();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$roleLabel Earnings Projection',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                    'Use current live commission and withdrawal rules to estimate growth.'),
                if (_validationMessage.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_validationMessage,
                      style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Form(
          key: _formKey,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: _amountLabel(),
                        border: const OutlineInputBorder()),
                    validator: _validatePositive,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _countCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: _countLabel(),
                        border: const OutlineInputBorder()),
                    validator: _validatePositive,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _daysCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Days per month',
                        border: OutlineInputBorder()),
                    validator: _validatePositive,
                  ),
                  const SizedBox(height: 10),
                  if (_isMerchant)
                    TextFormField(
                      controller: _platformRateCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Platform fee rate (%)',
                          border: OutlineInputBorder()),
                      validator: _validatePositive,
                    ),
                  if (_isMerchant) const SizedBox(height: 10),
                  if (_isMerchant)
                    SwitchListTile.adaptive(
                      value: _isTopTier,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Top-tier merchant'),
                      subtitle:
                          const Text('Apply 11/13 platform-fee incentive'),
                      onChanged: (v) => setState(() => _isTopTier = v),
                    ),
                  if ((_isDriver || _isInspector))
                    DropdownButtonFormField<String>(
                      value: _withdrawalSpeed,
                      decoration: const InputDecoration(
                          labelText: 'Withdrawal speed',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: 'standard', child: Text('Standard (0%)')),
                        DropdownMenuItem(
                            value: 'instant', child: Text('Instant (1%)')),
                      ],
                      onChanged: (v) =>
                          setState(() => _withdrawalSpeed = v ?? 'standard'),
                    ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _autosaveCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Autosave to MoneyBox (%)',
                      helperText: '1% to 30%',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateAutosave,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _calculate,
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('Calculate Projection'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                    label: 'Monthly gross',
                    value: _money(_result!['monthlyGross'] ?? 0)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  label: 'Platform commissions',
                  value: _money(_result!['monthlyCommission'] ?? 0),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                    label: 'Net earnings',
                    value: _money(_result!['monthlyNet'] ?? 0)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  label: 'Withdrawal fee',
                  value: _money(_result!['monthlyWithdrawalFee'] ?? 0),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Take-home after withdrawal',
                  value: _money(_result!['monthlyTakeHome'] ?? 0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  label: 'Monthly autosave',
                  value: _money(_result!['monthlyAutosave'] ?? 0),
                ),
              ),
            ],
          ),
          if (_isMerchant && (_result!['monthlyIncentive'] ?? 0) > 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Top-tier incentive added: ${_money(_result!['monthlyIncentive'] ?? 0)} monthly.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          const SizedBox(height: 12),
          ProjectionTable(rows: _projectionRows, money: _money),
          const SizedBox(height: 12),
          MoneyboxProjectionTable(rows: _moneyBoxRows, money: _money),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Early Withdrawal Penalty Illustration',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text('First third of lock period: 7% penalty'),
                  Text('Second third of lock period: 5% penalty'),
                  Text('Final third of lock period: 2% penalty'),
                  Text('At maturity: 0% penalty'),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(value,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}
