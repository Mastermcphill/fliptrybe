import 'package:flutter/material.dart';

import '../../services/order_service.dart';
import '../../ui/components/ft_components.dart';
import '../../utils/formatters.dart';
import '../../widgets/transaction/transaction_timeline_step.dart';

class TransactionTimelineScreen extends StatefulWidget {
  const TransactionTimelineScreen({
    super.key,
    required this.orderId,
    this.autoLoad = true,
    this.initialOrder,
    this.initialDelivery,
    this.initialEvents,
  });

  final int orderId;
  final bool autoLoad;
  final Map<String, dynamic>? initialOrder;
  final Map<String, dynamic>? initialDelivery;
  final List<dynamic>? initialEvents;

  @override
  State<TransactionTimelineScreen> createState() =>
      _TransactionTimelineScreenState();
}

class _TransactionTimelineScreenState extends State<TransactionTimelineScreen> {
  final OrderService _orderService = OrderService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _order = const {};
  Map<String, dynamic> _delivery = const {};
  List<Map<String, dynamic>> _events = const [];

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _load();
    } else {
      _order = Map<String, dynamic>.from(widget.initialOrder ?? const {});
      _delivery = Map<String, dynamic>.from(widget.initialDelivery ?? const {});
      _events = (widget.initialEvents ?? const [])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      _loading = false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _orderService.getOrder(widget.orderId),
        _orderService.getDelivery(widget.orderId),
        _orderService.timeline(widget.orderId),
      ]);
      if (!mounted) return;
      final orderRes = values[0];
      final order = orderRes is Map
          ? Map<String, dynamic>.from(orderRes as Map)
          : <String, dynamic>{};
      final deliveryAny = values[1];
      final deliveryRes = deliveryAny is Map
          ? Map<String, dynamic>.from(deliveryAny as Map)
          : <String, dynamic>{};
      final deliveryRaw = deliveryRes['delivery'];
      final delivery = deliveryRaw is Map
          ? Map<String, dynamic>.from(deliveryRaw as Map)
          : Map<String, dynamic>.from(deliveryRes);
      final timelineAny = values[2];
      final events = (timelineAny is List ? timelineAny : const <dynamic>[])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      setState(() {
        _order = order;
        _delivery = delivery;
        _events = events;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load transaction timeline.';
        _loading = false;
      });
    }
  }

  String _money(dynamic value) {
    return formatNaira(value);
  }

  String _escrowStatus() {
    final fromOrder = (_order['escrow_status'] ?? '').toString().trim();
    final fromDelivery = (_delivery['escrow_status'] ?? '').toString().trim();
    if (fromOrder.isNotEmpty) return fromOrder;
    if (fromDelivery.isNotEmpty) return fromDelivery;
    return 'held';
  }

  bool _containsEvent(Iterable<String> keywords) {
    for (final event in _events) {
      final combined =
          '${event['event'] ?? ''} ${event['note'] ?? ''}'.toLowerCase();
      if (keywords.any((keyword) => combined.contains(keyword.toLowerCase()))) {
        return true;
      }
    }
    return false;
  }

  bool _boolField(String key) {
    final inDelivery = _delivery[key];
    final inOrder = _order[key];
    final raw = inDelivery ?? inOrder;
    return raw == true ||
        raw?.toString().toLowerCase() == 'true' ||
        raw?.toString() == '1';
  }

  String _stepStatus({required bool done, required bool cancelled}) {
    if (done) return 'Completed';
    if (cancelled) return 'Cancelled';
    return 'Pending';
  }

  Map<String, bool> _channelsForStep(String key) {
    final fallback = <String, bool>{
      'inapp': true,
      'sms': false,
      'wa': false,
    };
    for (final event in _events) {
      final name = (event['event'] ?? '').toString().toLowerCase();
      final note = (event['note'] ?? '').toString().toLowerCase();
      final target = '$name $note';
      if (!target.contains(key.toLowerCase())) continue;
      return <String, bool>{
        'inapp': true,
        'sms': event['sms_sent'] == true ||
            event['notified_sms'] == true ||
            note.contains('sms'),
        'wa': event['whatsapp_sent'] == true ||
            event['notified_whatsapp'] == true ||
            note.contains('whatsapp'),
      };
    }
    return fallback;
  }

  List<TransactionTimelineStep> _timelineWidgets() {
    final orderStatus = (_order['status'] ?? '').toString().toLowerCase();
    final cancelled = orderStatus.contains('cancel');
    final paid =
        (_order['payment_status'] ?? '').toString().toLowerCase() == 'paid' ||
            _containsEvent(['payment', 'paid', 'paystack']);
    final inspectorRequested = _boolField('inspection_requested') ||
        (_order['inspection_fee'] ?? 0).toString() != '0' ||
        _containsEvent(['inspection']);

    final driverAssigned = (_order['driver_id'] ?? '').toString().isNotEmpty ||
        _containsEvent(['driver_assigned']) ||
        orderStatus.contains('assigned');
    final pickupDone =
        (_delivery['pickup_confirmed_at'] ?? '').toString().trim().isNotEmpty ||
            _containsEvent(['pickup_confirmed']) ||
            orderStatus.contains('picked_up');
    final dropoffDone = (_delivery['dropoff_confirmed_at'] ?? '')
            .toString()
            .trim()
            .isNotEmpty ||
        _containsEvent(['delivery_confirmed', 'dropoff_confirmed']) ||
        orderStatus.contains('delivered') ||
        orderStatus.contains('completed');
    final escrowReleased = _escrowStatus().toLowerCase().contains('released') ||
        _containsEvent(['escrow_released']) ||
        orderStatus == 'completed';
    final walletCredited =
        (_order['wallet_credited_at'] ?? '').toString().trim().isNotEmpty ||
            _containsEvent(['wallet_credited', 'payout']) ||
            orderStatus == 'completed';

    final stepData = <Map<String, dynamic>>[
      {
        'title': 'Listing Created',
        'done': (_order['listing_id'] ?? '').toString().isNotEmpty,
        'key': 'listing',
        'subtitle': 'Merchant created the listing record.',
      },
      {
        'title': 'Availability Confirmed',
        'done': _containsEvent(['availability_confirmed']) ||
            [
              'accepted',
              'merchant_accepted',
              'assigned',
              'picked_up',
              'delivered',
              'completed'
            ].contains(orderStatus),
        'key': 'availability',
        'subtitle':
            'Merchant confirmed availability before checkout progression.',
      },
      {
        'title': 'Buyer Paid',
        'done': paid,
        'key': 'payment',
        'subtitle': 'Payment captured and tied to order reference.',
      },
      {
        'title': 'Escrow Created',
        'done': paid ||
            _containsEvent(['escrow']) ||
            _escrowStatus().toLowerCase() == 'held',
        'key': 'escrow',
        'subtitle':
            'Escrow now holds transaction funds pending workflow completion.',
      },
      {
        'title': 'Inspector Booked (if applicable)',
        'done': inspectorRequested &&
            (_containsEvent(['inspection_booked']) ||
                (_order['inspector_id'] ?? '').toString().isNotEmpty),
        'key': 'inspection_booked',
        'subtitle': inspectorRequested
            ? 'Inspection booking requested by buyer.'
            : 'Optional step. Buyer did not request inspection yet.',
      },
      {
        'title': 'Inspection Completed (if applicable)',
        'done': inspectorRequested &&
            _containsEvent(['inspection_completed', 'report_submitted']),
        'key': 'inspection_completed',
        'subtitle': inspectorRequested
            ? 'Inspector submitted results and media.'
            : 'Optional step. Inspection was not required.',
      },
      {
        'title': 'Driver Assigned',
        'done': driverAssigned,
        'key': 'driver_assigned',
        'subtitle': 'Delivery driver accepted assignment.',
      },
      {
        'title': 'Pickup Confirmed',
        'done': pickupDone,
        'key': 'pickup_confirmed',
        'subtitle': 'Pickup code or QR confirmation completed.',
      },
      {
        'title': 'Delivery Confirmed',
        'done': dropoffDone,
        'key': 'delivery_confirmed',
        'subtitle': 'Delivery code or QR confirmation completed.',
      },
      {
        'title': 'Escrow Released',
        'done': escrowReleased,
        'key': 'escrow_released',
        'subtitle': 'Escrow moved from held status to payout-ready.',
      },
      {
        'title': 'Wallet Credited',
        'done': walletCredited,
        'key': 'wallet_credited',
        'subtitle': 'Role payouts credited to recipient wallets.',
      },
    ];

    return stepData.map((step) {
      final channels = _channelsForStep(step['key'].toString());
      return TransactionTimelineStep(
        title: step['title'].toString(),
        status: _stepStatus(
          done: step['done'] == true,
          cancelled: cancelled,
        ),
        subtitle: step['subtitle'].toString(),
        escrowStatus: _escrowStatus(),
        notifiedInApp: channels['inapp'] ?? true,
        notifiedSms: channels['sms'] ?? false,
        notifiedWhatsApp: channels['wa'] ?? false,
      );
    }).toList();
  }

  Widget _escrowSummaryCard() {
    final itemPrice = double.tryParse(
          (_order['base_price'] ?? _order['amount'] ?? 0).toString(),
        ) ??
        0;
    final platformFee =
        double.tryParse((_order['platform_fee'] ?? 0).toString()) ?? 0;
    final inspectionFee =
        double.tryParse((_order['inspection_fee'] ?? 0).toString()) ?? 0;
    final deliveryFee =
        double.tryParse((_order['delivery_fee'] ?? 0).toString()) ?? 0;
    final totalFromOrder =
        double.tryParse((_order['total_price'] ?? 0).toString()) ?? 0;
    final escrowTotal = totalFromOrder > 0
        ? totalFromOrder
        : itemPrice + platformFee + inspectionFee + deliveryFee;
    final escrow = _escrowStatus().toLowerCase();
    final released = escrow.contains('released') || escrow.contains('paid');

    final merchantPayout = released
        ? (double.tryParse((_order['merchant_payout'] ?? 0).toString()) ??
            itemPrice)
        : 0;
    final driverPayout = released
        ? (double.tryParse((_order['driver_payout'] ?? 0).toString()) ??
            (deliveryFee * 0.9))
        : 0;
    final inspectorPayout = released
        ? (double.tryParse((_order['inspector_payout'] ?? 0).toString()) ??
            (inspectionFee * 0.9))
        : 0;
    final platformPayout = released
        ? (double.tryParse((_order['platform_payout'] ?? 0).toString()) ??
            (escrowTotal - merchantPayout - driverPayout - inspectorPayout))
        : 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escrow Summary',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text('Item price: ${_money(itemPrice)}'),
            Text('Platform fee: ${_money(platformFee)}'),
            Text('Inspection fee: ${_money(inspectionFee)}'),
            Text('Delivery fee: ${_money(deliveryFee)}'),
            const Divider(height: 18),
            Text('Escrow total: ${_money(escrowTotal)}'),
            Text('Escrow status: ${_escrowStatus()}'),
            if (released) ...[
              const SizedBox(height: 10),
              const Text(
                'Released Payout Split',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Table(
                border: TableBorder.all(color: const Color(0xFFCFD8DC)),
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFF0F2F5)),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Recipient',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Amount',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  TableRow(children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Merchant'),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_money(merchantPayout)),
                    ),
                  ]),
                  TableRow(children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Driver'),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_money(driverPayout)),
                    ),
                  ]),
                  TableRow(children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Inspector'),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_money(inspectorPayout)),
                    ),
                  ]),
                  TableRow(children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Platform'),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_money(platformPayout)),
                    ),
                  ]),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _messagingPanel() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications & Messaging',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'In-app messages keep the permanent transaction record.',
            ),
            Text(
              'SMS/WhatsApp channels are used for time-critical alerts.',
            ),
            Text(
              'When integrations are disabled or sandboxed, messages remain logged in queue for admin visibility.',
            ),
            Text(
              'When integrations are live, Termii dispatches automatically; failures appear in Notify Queue (admin only).',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Transaction Timeline #${widget.orderId}',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: _order.isEmpty,
        loadingState: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            FTSkeleton(height: 150),
            SizedBox(height: 10),
            FTSkeleton(height: 120),
            SizedBox(height: 10),
            FTSkeleton(height: 120),
          ],
        ),
        emptyState: const FTEmptyState(
          icon: Icons.timeline_outlined,
          title: 'No timeline data yet',
          subtitle:
              'This order has no transaction timeline records available right now.',
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _escrowSummaryCard(),
            const SizedBox(height: 10),
            const Text(
              'Order Lifecycle',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            ..._timelineWidgets(),
            const SizedBox(height: 6),
            _messagingPanel(),
          ],
        ),
      ),
    );
  }
}
