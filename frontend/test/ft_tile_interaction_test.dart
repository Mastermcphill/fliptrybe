import 'package:fliptrybe/ui/components/ft_tile.dart';
import 'package:fliptrybe/utils/unavailable_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FTTile without onTap is non-interactive and does not show chevron',
      (tester) async {
    const titleKey = Key('tile-title');
    const longTitle =
        'Recommended for you across city discovery and shortlet stays';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: FTTile(
              titleWidget: Text(longTitle, key: titleKey),
              subtitle: 'Non interactive tile',
              onTap: null,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(InkWell), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    final titleSize = tester.getSize(find.byKey(titleKey));
    expect(titleSize.width, greaterThan(150));
  });

  testWidgets('FTTile with onTap is interactive and shows chevron',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FTTile(
            title: 'Open details',
            onTap: () => tapped += 1,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(InkWell), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    await tester.tap(find.text('Open details'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('UnavailableActionHint renders reason text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UnavailableActionHint(
            reason: 'This action is disabled in this release.',
          ),
        ),
      ),
    );

    expect(find.text('This action is disabled in this release.'), findsOneWidget);
  });
}
