import 'package:flutter/material.dart';

import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';

class MoneyActionReceiptScreen extends StatelessWidget {
  const MoneyActionReceiptScreen({
    super.key,
    required this.title,
    required this.statusLabel,
    required this.amount,
    this.reference,
    this.destination,
    this.timestamp,
  });

  final String title;
  final String statusLabel;
  final double amount;
  final String? reference;
  final String? destination;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final when = timestamp ?? DateTime.now();
    return FTScaffold(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FTSection(
            title: 'Receipt',
            subtitle: 'Keep this reference for support follow-up.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(context, 'Status', statusLabel),
                const SizedBox(height: 8),
                _row(context, 'Amount', formatNaira(amount)),
                if ((destination ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _row(context, 'Destination', destination!),
                ],
                if ((reference ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _row(context, 'Reference', reference!),
                ],
                const SizedBox(height: 8),
                _row(context, 'Timestamp', when.toLocal().toString()),
              ],
            ),
          ),
          const Spacer(),
          FTPrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String key, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            key,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
