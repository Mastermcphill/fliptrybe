import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fliptrybe/screens/landing_screen.dart';
import 'package:fliptrybe/screens/role_signup_screen.dart';
import 'package:fliptrybe/screens/marketplace_screen.dart';
import 'package:fliptrybe/screens/marketplace_filters_screen.dart';
import 'package:fliptrybe/screens/listing_detail_screen.dart';

void main() {
  testWidgets('MaterialApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.shrink(),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Landing signup CTA routes to role chooser', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => LandingScreen(
            enableTicker: false,
            onLogin: () {},
            onSignup: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RoleSignupScreen()),
              );
            },
          ),
        ),
      ),
    );

    final signupFinder = find.text('Sign up (Choose role)');
    await tester.ensureVisible(signupFinder);
    await tester.pumpAndSettle();
    await tester.tap(signupFinder);
    await tester.pumpAndSettle();

    expect(find.byType(RoleSignupScreen), findsOneWidget);
  });

  testWidgets('Marketplace listing tap opens listing detail', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MarketplaceScreen()));
    await tester.pumpAndSettle();

    final itemFinder = find.text('iPhone 12 128GB');
    expect(itemFinder, findsOneWidget);

    await tester.ensureVisible(itemFinder);
    await tester.pumpAndSettle();
    await tester.tap(itemFinder);
    await tester.pumpAndSettle();

    expect(find.byType(ListingDetailScreen), findsOneWidget);
  });

  testWidgets('Marketplace filter icon opens filters screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MarketplaceScreen()));
    await tester.pumpAndSettle();

    final filterFinder = find.byTooltip('Filters');
    expect(filterFinder, findsOneWidget);
    await tester.tap(filterFinder);
    await tester.pumpAndSettle();

    expect(find.byType(MarketplaceFiltersScreen), findsOneWidget);
  });
}
