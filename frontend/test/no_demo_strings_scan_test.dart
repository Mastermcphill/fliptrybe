import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI code does not contain seed/demo placeholder strings', () async {
    final root = Directory('lib');
    expect(await root.exists(), isTrue);

    final forbidden = <String>[
      'Seed Listing',
      'seed listing',
      'demo-ready',
      'Investor demo actions',
      'Leave a review (demo)',
      'Broadcast sent (demo)',
      'Delete demo',
    ];

    final hits = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = await entity.readAsString();
      for (final token in forbidden) {
        if (text.contains(token)) {
          hits.add('${entity.path} -> $token');
        }
      }
    }

    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}

