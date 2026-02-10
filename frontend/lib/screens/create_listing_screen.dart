import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/listing_service.dart';
import '../services/feed_service.dart';
import '../services/api_service.dart';
import '../widgets/email_verification_dialog.dart';
import '../constants/ng_states.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _listingService = ListingService();
  final _feedService = FeedService();

  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  final _cityCtrl = TextEditingController();
  final _localityCtrl = TextEditingController();
  final _lgaCtrl = TextEditingController();

  String _state = 'Lagos';
  List<String> _states = const [];
  Map<String, List<String>> _citiesByState = const {};
  Map<String, List<String>> _majorCities = const {};

  File? _selectedImage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    final res = await _feedService.getLocations();

    final states = (res['states'] is List)
        ? (res['states'] as List).map((e) => e.toString()).toList()
        : <String>[];

    final cbs = <String, List<String>>{};
    if (res['cities_by_state'] is Map) {
      (res['cities_by_state'] as Map).forEach((k, v) {
        if (v is List) cbs[k.toString()] = v.map((e) => e.toString()).toList();
      });
    }

    final majors = <String, List<String>>{};
    if (res['major_cities'] is Map) {
      (res['major_cities'] as Map).forEach((k, v) {
        if (v is List) majors[k.toString()] = v.map((e) => e.toString()).toList();
      });
    }

    if (!mounted) return;
    setState(() {
      _states = states;
      _citiesByState = cbs;
      _majorCities = majors;
      if (_states.isNotEmpty && !_states.contains(_state)) _state = _states.first;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _cityCtrl.dispose();
    _localityCtrl.dispose();
    _lgaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => Container(
        height: 150,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text("Take Photo", style: TextStyle(color: Colors.white)),
              onTap: () async {
                final XFile? image = await picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 80,
                  maxWidth: 1400,
                );
                if (!mounted) return;
                if (image != null) setState(() => _selectedImage = File(image.path));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text("Choose from Gallery", style: TextStyle(color: Colors.white)),
              onTap: () async {
                final XFile? image = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 80,
                  maxWidth: 1400,
                );
                if (!mounted) return;
                if (image != null) setState(() => _selectedImage = File(image.path));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitListing() async {
    if (_isLoading) return;

    final title = _titleCtrl.text.trim();
    final priceText = _priceCtrl.text.trim();
    final desc = _descCtrl.text.trim();

    _cityCtrl.text.trim();
    _localityCtrl.text.trim();
    _lgaCtrl.text.trim();

    if (title.isEmpty || priceText.isEmpty || _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add a photo, title, and price.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    final price = double.tryParse(priceText) ?? 0;
    final res = await _listingService.createListing(
      title: title,
      description: desc,
      price: price,
      imagePath: _selectedImage!.path,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    final ok = res['ok'] == true;
    final msg = (res['message'] ?? res['error'] ?? 'Failed to upload. Try again.').toString();

    if (!ok && ApiService.isEmailNotVerified(res)) {
      await showEmailVerificationRequiredDialog(
        context,
        message: msg,
        onRetry: _submitListing,
      );
      return;
    }

    if (ok && res['listing'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Listing Posted!")));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateItems = (_states.isEmpty ? nigeriaStates : _states);

    final cities = _citiesByState[_state] ?? const <String>[];
    final majorCities = _majorCities[_state] ?? const <String>[];

    final cityChips = (cities.isNotEmpty ? cities : majorCities);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Sell Item", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade800),
                  image: _selectedImage != null
                      ? DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover)
                      : null,
                ),
                child: _selectedImage == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, color: Color(0xFF00C853), size: 40),
                          SizedBox(height: 10),
                          Text("Tap to add photo", style: TextStyle(color: Colors.grey)),
                        ],
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 30),
            _buildTextField("Title", "e.g. iPhone 13 Pro", _titleCtrl),
            const SizedBox(height: 20),
            _buildTextField("Price (₦)", "e.g. 450000", _priceCtrl, isNumber: true),
            const SizedBox(height: 20),
            const Text("State", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _state,
              items: stateItems
                  .map((s) => DropdownMenuItem(value: s, child: Text(displayState(s))))
                  .toList(),
              onChanged: (v) => setState(() => _state = (v ?? _state)),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            _buildTextField("City", "e.g. Lekki, Wuse, GRA...", _cityCtrl),
            if (cityChips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: cityChips.take(16).map((c) {
                  return ActionChip(label: Text(c), onPressed: () => _cityCtrl.text = c);
                }).toList(),
              ),
            ],
            const SizedBox(height: 20),
            _buildTextField("Locality / Area (optional)", "e.g. Chevron, Magodo, Rumuola...", _localityCtrl),
            const SizedBox(height: 20),
            _buildTextField("LGA (optional)", "e.g. Eti-Osa, AMAC, Obio-Akpor...", _lgaCtrl),
            const SizedBox(height: 20),
            _buildTextField("Description", "Describe the condition...", _descCtrl, maxLines: 4),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitListing,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C853),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Post Listing", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      backgroundColor: Colors.black,
    );
  }

  Widget _buildTextField(
    String label,
    String hint,
    TextEditingController controller, {
    bool isNumber = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade700),
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}
