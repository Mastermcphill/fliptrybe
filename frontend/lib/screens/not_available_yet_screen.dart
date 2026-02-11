import 'package:flutter/material.dart';

import 'support_chat_screen.dart';

class NotAvailableYetScreen extends StatelessWidget {
  final String title;
  final String reason;
  final bool showContactAdmin;

  const NotAvailableYetScreen({
    super.key,
    required this.title,
    required this.reason,
    this.showContactAdmin = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 46),
                const SizedBox(height: 12),
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                if (showContactAdmin) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SupportChatScreen()),
                      );
                    },
                    icon: const Icon(Icons.support_agent_outlined),
                    label: const Text('Contact Admin'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
