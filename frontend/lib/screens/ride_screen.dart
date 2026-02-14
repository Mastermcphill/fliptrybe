import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RideScreen extends StatefulWidget {
  const RideScreen({super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  String _selectedVehicle = "car"; // car, bike, van
  bool _submitting = false;

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  Future<void> _requestRide() async {
    if (_submitting) return;

    final pickup = _pickupController.text.trim();
    final dropoff = _dropoffController.text.trim();
    if (pickup.isEmpty || dropoff.isEmpty) return;

    setState(() => _submitting = true);

    // Show Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00C853)),
      ),
    );

    final success =
        await ApiService.requestRide(pickup, dropoff, _selectedVehicle);

    if (!mounted) return;

    // Close Loader (only if still possible)
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    setState(() => _submitting = false);

    if (success) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E1E1E),
        builder: (_) => Container(
          padding: const EdgeInsets.all(30),
          height: 250,
          child: const Column(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF00C853), size: 60),
              SizedBox(height: 20),
              Text(
                "Ride Requested!",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text("Searching for nearby drivers...",
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to find ride.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. THE MAP (Placeholder)
          Container(
            color: Colors.grey[900],
            width: double.infinity,
            height: double.infinity,
            child: const Center(
              child: Opacity(
                opacity: 0.3,
                child: Icon(Icons.map, size: 100, color: Colors.white),
              ),
            ),
          ),

          // 2. THE FLOATING CONTROLS
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(25),
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black54, blurRadius: 20, spreadRadius: 5)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Where to?",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  _buildLocationInput(
                      Icons.my_location, "Current Location", _pickupController),
                  const SizedBox(height: 15),
                  _buildLocationInput(Icons.location_on, "Enter Destination",
                      _dropoffController),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildVehicleOption("bike", Icons.two_wheeler),
                      _buildVehicleOption("car", Icons.directions_car),
                      _buildVehicleOption("van", Icons.local_shipping),
                    ],
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _requestRide,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C853),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                      ),
                      child: Text(
                        _submitting ? "Requesting..." : "Confirm FlipRide",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. BACK BUTTON (Top Left)
          Positioned(
            top: 50,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLocationInput(
      IconData icon, String hint, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.grey),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildVehicleOption(String type, IconData icon) {
    final isSelected = _selectedVehicle == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedVehicle = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00C853).withOpacity(0.2)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border:
              isSelected ? Border.all(color: const Color(0xFF00C853)) : null,
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isSelected ? const Color(0xFF00C853) : Colors.grey,
                size: 30),
            const SizedBox(height: 5),
            Text(
              type.toUpperCase(),
              style: TextStyle(
                color: isSelected ? const Color(0xFF00C853) : Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
