import 'package:flutter/material.dart';
import '../services/admin_service.dart';
import 'admin_lists_screen.dart';
import '../utils/auth_navigation.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _svc = AdminService();

  Future<void> _handleLogout() async {
    await logoutToLanding(context);
  }

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  final _userIdCtrl = TextEditingController();
  final _listingIdCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController(text: "disabled by admin");

  bool _actionBusy = false;
  String? _actionMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _listingIdCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _actionMsg = null;
    });
    try {
      final data = await _svc.overview();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int? _parseInt(String s) {
    final v = int.tryParse(s.trim());
    return v;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _disableUser() async {
    final id = _parseInt(_userIdCtrl.text);
    if (id == null) {
      _toast("Enter a valid user id");
      return;
    }
    setState(() {
      _actionBusy = true;
      _actionMsg = null;
    });
    try {
      final res = await _svc.disableUser(
          userId: id,
          reason: _reasonCtrl.text.trim().isEmpty
              ? "disabled by admin"
              : _reasonCtrl.text.trim());
      final ok = res["ok"] == true;
      final msg = ok ? "User #$id disabled" : "Failed to disable user";
      if (!mounted) return;
      setState(() {
        _actionMsg = msg;
      });
      _toast(msg);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionMsg = e.toString();
      });
      _toast("Error: $e");
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  Future<void> _disableListing() async {
    final id = _parseInt(_listingIdCtrl.text);
    if (id == null) {
      _toast("Enter a valid listing id");
      return;
    }
    setState(() {
      _actionBusy = true;
      _actionMsg = null;
    });
    try {
      final res = await _svc.disableListing(
          listingId: id,
          reason: _reasonCtrl.text.trim().isEmpty
              ? "disabled by admin"
              : _reasonCtrl.text.trim());
      final ok = res["ok"] == true;
      final msg = ok
          ? "Listing #$id disabled (hidden from feed)"
          : "Failed to disable listing";
      if (!mounted) return;
      setState(() {
        _actionMsg = msg;
      });
      _toast(msg);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionMsg = e.toString();
      });
      _toast("Error: $e");
    } finally {
      if (mounted) {
        setState(() => _actionBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _data?['counts'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Overview"),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
          ),
          IconButton(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 40),
                    const Icon(Icons.admin_panel_settings_outlined, size: 44),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                        onPressed: _load, child: const Text("Retry")),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text("Users: ${counts?['users'] ?? 0}",
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 6),
                    Text("Listings: ${counts?['listings'] ?? 0}",
                        style: const TextStyle(fontSize: 16)),
                    const Divider(height: 28),
                    const Text("Disable Controls",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AdminListsScreen()),
                        );
                      },
                      child: const Text("Admin Lists"),
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: "Reason",
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _userIdCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "User ID",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _actionBusy ? null : _disableUser,
                          child: const Text("Disable User"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _listingIdCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Listing ID",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _actionBusy ? null : _disableListing,
                          child: const Text("Disable Listing"),
                        ),
                      ],
                    ),
                    if (_actionMsg != null) ...[
                      const SizedBox(height: 14),
                      Text(_actionMsg!,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 18),
                    const Text(
                      "Note: disabling a listing hides it from the feed immediately (backend filter).",
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
    );
  }
}
