import 'package:flutter/material.dart';

import '../services/driver_directory_service.dart';
import '../utils/auth_navigation.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final _svc = DriverDirectoryService();

  Future<void> _handleLogout() async {
    await logoutToLanding(context);
  }

  final _phone = TextEditingController();
  final _vehicle = TextEditingController(text: "bike");
  final _plate = TextEditingController();
  final _state = TextEditingController(text: "Lagos");
  final _city = TextEditingController(text: "Ikeja");
  final _locality = TextEditingController(text: "Alausa");

  bool _active = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await _svc.getMyDriverProfile();
    if (p != null) {
      _phone.text = (p['phone'] ?? '').toString();
      _vehicle.text = (p['vehicle_type'] ?? 'bike').toString();
      _plate.text = (p['plate_number'] ?? '').toString();
      _state.text = (p['state'] ?? 'Lagos').toString();
      _city.text = (p['city'] ?? 'Ikeja').toString();
      _locality.text = (p['locality'] ?? 'Alausa').toString();
      _active = p['is_active'] == true;
    }
    setState(() => _loading = false);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final ok = await _svc.saveMyDriverProfile(
      phone: _phone.text,
      vehicleType: _vehicle.text,
      plateNumber: _plate.text,
      state: _state.text,
      city: _city.text,
      locality: _locality.text,
      isActive: _active,
    );
    _toast(ok ? "Driver profile saved ✅" : "Save failed");
  }

  @override
  void dispose() {
    _phone.dispose();
    _vehicle.dispose();
    _plate.dispose();
    _state.dispose();
    _city.dispose();
    _locality.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Profile"),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save)),
          IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              onPressed: _handleLogout,
              tooltip: 'Sign out'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                    "This sets your delivery coverage so merchants can assign you.",
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                    controller: _phone,
                    decoration: const InputDecoration(
                        labelText: "Phone", border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                    controller: _vehicle,
                    decoration: const InputDecoration(
                        labelText: "Vehicle type (bike/car/van)",
                        border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                    controller: _plate,
                    decoration: const InputDecoration(
                        labelText: "Plate number",
                        border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                    controller: _state,
                    decoration: const InputDecoration(
                        labelText: "State", border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                    controller: _city,
                    decoration: const InputDecoration(
                        labelText: "City", border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                    controller: _locality,
                    decoration: const InputDecoration(
                        labelText: "Locality", border: OutlineInputBorder())),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text("Active (available for jobs)"),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_circle),
                  label: const Text("Save"),
                ),
              ],
            ),
    );
  }
}
