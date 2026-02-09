import 'package:flutter/material.dart';

import '../services/order_service.dart';
import '../services/driver_directory_service.dart';
import '../services/auth_service.dart';
import 'receipts_by_order_screen.dart';
import 'receipts_screen.dart';
import 'support_tickets_screen.dart';
import 'support_chat_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final _svc = OrderService();
  final _driversSvc = DriverDirectoryService();
  final _auth = AuthService();

  List<dynamic> _drivers = const [];
  int? _selectedDriverId;
  final _driverFilterState = TextEditingController();
  final _driverFilterCity = TextEditingController();
  final _driverFilterLocality = TextEditingController();

  final _filterState = TextEditingController();
  final _filterCity = TextEditingController();
  final _filterLocality = TextEditingController();

  final _pickupCodeCtrl = TextEditingController();
  final _deliveryCodeCtrl = TextEditingController();
  final _qrTokenCtrl = TextEditingController();

  String? _lastIssuedToken;
  String? _lastIssuedStep;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _order;
  Map<String, dynamic>? _delivery;
  List<dynamic> _events = const [];

  String _role = 'buyer';
  int? _viewerId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _auth.me();
    if (!mounted) return;
    setState(() {
      _role = (profile?['role'] ?? 'buyer').toString();
      final idVal = profile?['id'];
      _viewerId = idVal is int ? idVal : int.tryParse(idVal?.toString() ?? '');
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _svc.getOrder(widget.orderId);
      final tl = await _svc.timeline(widget.orderId);
      final delivery = await _svc.getDelivery(widget.orderId);
      final drivers = await _driversSvc.listDrivers(
        state: _driverFilterState.text,
        city: _driverFilterCity.text,
        locality: _driverFilterLocality.text,
      );

      setState(() {
        _order = detail;
        _delivery = (delivery['delivery'] is Map) ? Map<String, dynamic>.from(delivery['delivery'] as Map) : null;
        _events = tl;
        _drivers = drivers;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshDelivery() async {
    final delivery = await _svc.getDelivery(widget.orderId);
    if (!mounted) return;
    setState(() {
      _delivery = (delivery['delivery'] is Map) ? Map<String, dynamic>.from(delivery['delivery'] as Map) : _delivery;
    });
  }

  Future<void> _merchantAccept() async {
    final ok = await _svc.merchantAccept(widget.orderId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? "Merchant accepted ✅" : "Not allowed / failed")));
    if (ok) _load();
  }

  Future<void> _assignDriver() async {
    final did = _selectedDriverId;
    if (did == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a driver first')));
      return;
    }
    final ok = await _svc.assignDriver(widget.orderId, did);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Driver assigned ✅' : 'Not allowed / failed')));
    if (ok) _load();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _issuePickupQr() async {
    final res = await _svc.issueQr(widget.orderId, "pickup_seller");
    final ok = res["ok"] == true;
    final data = res["data"];
    final token = (data is Map && data["token"] != null) ? data["token"].toString() : "";
    if (ok && token.isNotEmpty) {
      setState(() {
        _lastIssuedToken = token;
        _lastIssuedStep = "pickup_seller";
        _qrTokenCtrl.text = token;
      });
      _toast("Pickup QR issued");
      return;
    }
    _toast((data is Map && data["message"] != null) ? data["message"].toString() : "QR issue failed");
  }

  Future<void> _issueDeliveryQr() async {
    final res = await _svc.issueQr(widget.orderId, "delivery_driver");
    final ok = res["ok"] == true;
    final data = res["data"];
    final token = (data is Map && data["token"] != null) ? data["token"].toString() : "";
    if (ok && token.isNotEmpty) {
      setState(() {
        _lastIssuedToken = token;
        _lastIssuedStep = "delivery_driver";
        _qrTokenCtrl.text = token;
      });
      _toast("Delivery QR issued");
      return;
    }
    _toast((data is Map && data["message"] != null) ? data["message"].toString() : "QR issue failed");
  }

  Future<void> _scanQr() async {
    final token = _qrTokenCtrl.text.trim();
    if (token.isEmpty) {
      _toast("QR token required");
      return;
    }
    final res = await _svc.scanQr(widget.orderId, token);
    final ok = res["ok"] == true;
    final data = res["data"];
    if (ok) {
      _toast("QR scanned");
      _load();
      return;
    }
    final msg = (data is Map && data["message"] != null) ? data["message"].toString() : "QR scan failed";
    _toast(msg);
  }


  Future<void> _sellerConfirmPickup() async {
    final code = _pickupCodeCtrl.text.trim();
    if (code.isEmpty) {
      _toast("Pickup code required");
      return;
    }
    final res = await _svc.sellerConfirmPickup(widget.orderId, code);
    final ok = res["ok"] == true;
    final status = res["status"] ?? 0;
    final data = res["data"];
    if (ok) {
      _toast("Pickup confirmed ?");
      _load();
      return;
    }
    if (status == 423) {
      _toast("Pickup locked after too many attempts");
      return;
    }
    final msg = (data is Map && data["message"] != null) ? data["message"].toString() : "Pickup confirm failed";
    _toast(msg);
  }

  Future<void> _driverConfirmDelivery() async {
    final code = _deliveryCodeCtrl.text.trim();
    if (code.isEmpty) {
      _toast("Delivery code required");
      return;
    }
    final res = await _svc.driverConfirmDelivery(widget.orderId, code);
    final ok = res["ok"] == true;
    final status = res["status"] ?? 0;
    final data = res["data"];
    if (ok) {
      _toast("Delivery confirmed ?");
      _load();
      return;
    }
    if (status == 423) {
      _toast("Delivery locked after too many attempts");
      return;
    }
    final msg = (data is Map && data["message"] != null) ? data["message"].toString() : "Delivery confirm failed";
    _toast(msg);
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.grey.shade200,
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _progressStep(String label, bool done) {
    return Row(
      children: [
        Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: done ? Colors.green : Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }

  Widget _eventTile(Map<String, dynamic> m) {
    final at = (m['created_at'] ?? '').toString();
    final label = (m['event'] ?? '').toString();
    final note = (m['note'] ?? '').toString();
    return ListTile(
      dense: true,
      leading: const Icon(Icons.check_circle_outline),
      title: Text(label),
      subtitle: Text(note.isEmpty ? at : "$note\n$at"),
    );
  }

  @override
  Widget build(BuildContext context) {
    final delivery = _delivery ?? const <String, dynamic>{};
    final status = (delivery['status'] ?? _order?['status'] ?? '').toString();
    final role = _role.toLowerCase();
    final isAdmin = role == 'admin';
    final isMerchant = role == 'merchant';
    final isDriver = role == 'driver';
    final isBuyer = role == 'buyer';
    final statusLower = status.toLowerCase();
    final isDone = statusLower == 'delivered' || statusLower == 'completed' || statusLower == 'cancelled';
    final pickupCode = (delivery['pickup_code'] ?? _order?['pickup_code'] ?? '').toString();
    final deliveryCode = (delivery['dropoff_code'] ?? _order?['dropoff_code'] ?? _order?['delivery_code'] ?? '').toString();
    final pickupAttemptsLeft = (delivery['pickup_attempts_left'] ?? _order?['pickup_attempts_left'] ?? '').toString();
    final deliveryAttemptsLeft = (delivery['dropoff_attempts_left'] ?? _order?['delivery_attempts_left'] ?? '').toString();
    final canScanQr = (isAdmin || isMerchant || isDriver) && !isDone;
    final canIssuePickupQr = (isDriver || isAdmin) && !isDone;
    final canIssueDeliveryQr = (isBuyer || isAdmin) && !isDone;
    final canShowPickupCode = (isMerchant || isAdmin) && pickupCode.isNotEmpty;
    final canShowDeliveryCode = (isDriver || isAdmin || isBuyer) && deliveryCode.isNotEmpty;
    final canConfirmPickup = (isMerchant || isAdmin) && !['picked_up', 'delivered', 'completed', 'cancelled'].contains(statusLower);
    final canConfirmDelivery = (isDriver || isAdmin) && statusLower == 'picked_up';

    return Scaffold(
      appBar: AppBar(
        title: Text("Order #${widget.orderId}"),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _pill("Status: $status"),
                    const SizedBox(height: 12),

                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiptsScreen()));
                      },
                      icon: const Icon(Icons.receipt_long),
                      label: const Text("View Receipts"),
                    ),

                    const SizedBox(height: 12),
                    Text(
                      "Amount: ₦${_order?['amount'] ?? 0}",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text("Delivery Fee: ₦${_order?['delivery_fee'] ?? 0}", style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    if ((_order?['pickup'] ?? '').toString().isNotEmpty) Text("Pickup: ${_order?['pickup']}"),
                    if ((_order?['dropoff'] ?? '').toString().isNotEmpty) Text("Dropoff: ${_order?['dropoff']}"),
                    const SizedBox(height: 14),

                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (isMerchant || isAdmin)
                          ElevatedButton.icon(
                            onPressed: _merchantAccept,
                            icon: const Icon(Icons.storefront),
                            label: const Text("Merchant Accept"),
                          ),
                        if (canIssuePickupQr)
                          OutlinedButton.icon(
                            onPressed: _issuePickupQr,
                            icon: const Icon(Icons.qr_code_2),
                            label: const Text("Issue Pickup QR"),
                          ),
                        if (canIssueDeliveryQr)
                          OutlinedButton.icon(
                            onPressed: _issueDeliveryQr,
                            icon: const Icon(Icons.qr_code_2),
                            label: const Text("Issue Delivery QR"),
                          ),
                        if (canScanQr)
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _qrTokenCtrl,
                              decoration: InputDecoration(
                                labelText: 'QR token',
                                helperText: _lastIssuedToken != null ? "Issued step: ${_lastIssuedStep ?? ''}" : null,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        if (canScanQr)
                          OutlinedButton.icon(
                            onPressed: _scanQr,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text("Scan QR"),
                          ),
                        if (canShowPickupCode)
                          OutlinedButton(
                            onPressed: null,
                            child: Text("Dispatch code: $pickupCode"),
                          ),
                        if (canShowDeliveryCode)
                          OutlinedButton(
                            onPressed: null,
                            child: Text("Delivery code: $deliveryCode"),
                          ),
                        if (canConfirmPickup)
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _pickupCodeCtrl,
                              decoration: InputDecoration(
                                labelText: 'Pickup code',
                                helperText: pickupAttemptsLeft.isNotEmpty ? "Attempts left: $pickupAttemptsLeft" : null,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        if (canConfirmPickup)
                          ElevatedButton.icon(
                            onPressed: _sellerConfirmPickup,
                            icon: const Icon(Icons.local_shipping_outlined),
                            label: const Text("Seller Confirm Pickup"),
                          ),
                        if (canConfirmDelivery)
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _deliveryCodeCtrl,
                              decoration: InputDecoration(
                                labelText: 'Delivery code',
                                helperText: deliveryAttemptsLeft.isNotEmpty ? "Attempts left: $deliveryAttemptsLeft" : null,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        if (canConfirmDelivery)
                          ElevatedButton.icon(
                            onPressed: _driverConfirmDelivery,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text("Driver Confirm Delivery"),
                          ),
                        if (isMerchant && pickupCode.isEmpty)
                          const Text(
                            "Pickup code will arrive via SMS after QR issue. Enter it here to confirm pickup.",
                            style: TextStyle(color: Colors.black87),
                          ),
                        if (isDriver && deliveryCode.isEmpty)
                          const Text(
                            "Ask the buyer for the delivery code after dropoff to confirm delivery.",
                            style: TextStyle(color: Colors.black87),
                          ),
                        if (isBuyer)
                          Text(
                            deliveryCode.isNotEmpty
                                ? "Share this delivery code with the driver to confirm delivery."
                                : "Delivery code will arrive via SMS after pickup. Share it with the driver to confirm delivery.",
                            style: const TextStyle(color: Colors.black87),
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    const Text("Delivery Progress", style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _progressStep("Merchant accepted", ["merchant_accepted", "driver_assigned", "picked_up", "delivered", "completed"].contains(statusLower)),
                    const SizedBox(height: 4),
                    _progressStep("Pickup confirmed", (delivery['pickup_confirmed_at'] ?? '').toString().isNotEmpty),
                    const SizedBox(height: 4),
                    _progressStep("Delivery confirmed", (delivery['dropoff_confirmed_at'] ?? '').toString().isNotEmpty || ["delivered", "completed"].contains(statusLower)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _refreshDelivery,
                          icon: const Icon(Icons.refresh),
                          label: const Text("Refresh delivery status"),
                        ),
                        const SizedBox(width: 10),
                        if ((pickupCode.isEmpty && deliveryCode.isEmpty))
                          const Flexible(
                            child: Text("Codes not ready yet. Tap refresh or contact Admin for help.", style: TextStyle(color: Colors.black87)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SupportChatScreen()),
                        );
                      },
                      icon: const Icon(Icons.support_agent),
                      label: const Text("Contact Admin Support"),
                    ),
                    const Divider(height: 28),
                    const Text("Timeline", style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (_events.isEmpty)
                      const Text("No events yet.")
                    else
                      ..._events.whereType<Map>().map((e) => _eventTile(Map<String, dynamic>.from(e))),
                  ],
                ),
    );
  }
}
