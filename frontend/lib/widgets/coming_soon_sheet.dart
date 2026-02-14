import 'package:flutter/material.dart';

class ComingSoonSheet {
  static void show(
    BuildContext context, {
    String title = "Coming Soon",
    String message =
        "This feature is wired and planned. Next build will enable it fully.",
  }) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 10),
              Text(message),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
