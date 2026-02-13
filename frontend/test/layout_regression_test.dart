import 'package:fliptrybe/ui/components/ft_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Responsive title action keeps long text width readable',
      (tester) async {
    const subtitle =
        'Used on merchant profile, listing seller badge, and leaderboards.';

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: FTCard(
                child: FTResponsiveTitleAction(
                  title: 'Merchant Photo',
                  subtitle: subtitle,
                  action: FTButton(
                    label: 'Upload Photo',
                    variant: FTButtonVariant.ghost,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textFinder = find.text(subtitle);
    expect(textFinder, findsOneWidget);
    final size = tester.getSize(textFinder);
    expect(size.width, greaterThan(150));
  });
}
