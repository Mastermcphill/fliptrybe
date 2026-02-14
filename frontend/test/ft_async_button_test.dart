import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/ui/components/ft_async_button.dart';

void main() {
  testWidgets('FTAsyncButton prevents double submit while running',
      (tester) async {
    final completer = Completer<void>();
    var count = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FTAsyncButton(
              label: 'Submit',
              onPressed: () async {
                count += 1;
                await completer.future;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Submit'));
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(count, 1);

    completer.complete();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(count, 2);
  });
}
