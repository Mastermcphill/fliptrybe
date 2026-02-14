import 'package:flutter/material.dart';

import '../../utils/formatters.dart';
import 'ft_components.dart';

class FTMoneyConfirmationPayload {
  const FTMoneyConfirmationPayload({
    required this.title,
    required this.amount,
    required this.total,
    this.fee = 0,
    this.destination,
    this.reference,
    this.actionLabel = 'Confirm',
  });

  final String title;
  final double amount;
  final double fee;
  final double total;
  final String? destination;
  final String? reference;
  final String actionLabel;
}

Future<bool> showMoneyConfirmationSheet(
  BuildContext context,
  FTMoneyConfirmationPayload payload,
) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FTSectionHeader(
              title: payload.title,
              subtitle: 'Please confirm before we continue.',
            ),
            const SizedBox(height: 12),
            FTCard(
              child: Column(
                children: [
                  _moneyRow(ctx, 'Amount', payload.amount),
                  const SizedBox(height: 8),
                  _moneyRow(ctx, 'Fee', payload.fee),
                  const SizedBox(height: 8),
                  _moneyRow(
                    ctx,
                    'Total',
                    payload.total,
                    emphasize: true,
                  ),
                  if ((payload.destination ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _textRow(ctx, 'Destination', payload.destination!),
                  ],
                  if ((payload.reference ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _textRow(ctx, 'Reference', payload.reference!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            FTPrimaryCtaRow(
              primaryLabel: payload.actionLabel,
              onPrimary: () => Navigator.of(ctx).pop(true),
              secondaryLabel: 'Cancel',
              onSecondary: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    ),
  );
  return accepted == true;
}

Widget _moneyRow(BuildContext context, String label, double amount,
    {bool emphasize = false}) {
  final style = emphasize
      ? Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w800)
      : Theme.of(context).textTheme.bodyMedium;
  return Row(
    children: [
      Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      Text(formatNaira(amount), style: style),
    ],
  );
}

Widget _textRow(BuildContext context, String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 2,
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
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
