import 'package:fliptrybe/ui/foundation/components/ft_bottom_sheet.dart';
import 'package:fliptrybe/ui/foundation/theme/ft_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Fade-slide transition builder is available', () {
    const builder = FTFadeSlidePageTransitionsBuilder();
    expect(builder, isA<PageTransitionsBuilder>());
  });

  testWidgets('FTBottomSheet renders provided content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    FTBottomSheet.show<void>(
                      context: context,
                      builder: (_) => const Text('Sheet content'),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Sheet content'), findsOneWidget);
  });
}
