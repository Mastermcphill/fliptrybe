import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';

class AdminListsScreen extends StatefulWidget {
  const AdminListsScreen({super.key});

  @override
  State<AdminListsScreen> createState() => _AdminListsScreenState();
}

class _AdminListsScreenState extends State<AdminListsScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _users = const [];
  List<dynamic> _listings = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users =
          await ApiClient.instance.getJson(ApiConfig.api("/admin/users"));
      final listings =
          await ApiClient.instance.getJson(ApiConfig.api("/admin/listings"));
      if (!mounted) return;
      setState(() {
        _users = users is List ? users : const [];
        _listings = listings is List ? listings : const [];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Lists"),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    const Text("Users",
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ..._users.take(20).map((u) {
                      final m = (u as Map).cast<String, dynamic>();
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline),
                        title: Text(m['name']?.toString() ?? "User"),
                        subtitle: Text("id: ${m['id']} • ${m['email'] ?? ''}"),
                      );
                    }),
                    const Divider(height: 28),
                    const Text("Listings",
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    ..._listings.take(20).map((l) {
                      final m = (l as Map).cast<String, dynamic>();
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(m['title']?.toString() ?? "Listing"),
                        subtitle: Text(
                            "id: ${m['id']} • seller: ${m['seller_id'] ?? ''} • ₦${m['price'] ?? ''}"),
                      );
                    }),
                  ],
                ),
    );
  }
}
