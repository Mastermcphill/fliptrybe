import 'package:flutter/material.dart';

class HowItWorksTimelineStep extends StatelessWidget {
  const HowItWorksTimelineStep({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.check_circle_outline,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
