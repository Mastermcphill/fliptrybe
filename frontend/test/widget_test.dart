import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fliptrybe/screens/landing_screen.dart';
import 'package:fliptrybe/screens/role_signup_screen.dart';
import 'package:fliptrybe/screens/marketplace_screen.dart';
import 'package:fliptrybe/screens/marketplace_filters_screen.dart';
import 'package:fliptrybe/screens/listing_detail_screen.dart';
import 'package:fliptrybe/screens/admin_overview_screen.dart';
import 'package:fliptrybe/screens/buyer_home_screen.dart';
import 'package:fliptrybe/screens/merchant_home_screen.dart';
import 'package:fliptrybe/shells/admin_shell.dart';
import 'package:fliptrybe/shells/buyer_shell.dart';
import 'package:fliptrybe/shells/driver_shell.dart';
import 'package:fliptrybe/shells/inspector_shell.dart';
import 'package:fliptrybe/shells/merchant_shell.dart';

void main() {
  testWidgets('MaterialApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.shrink(),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Landing signup CTA routes to role chooser',
      (WidgetTester tester) async {
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

  testWidgets('Marketplace listing tap opens listing detail',
      (WidgetTester tester) async {
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

  testWidgets('Marketplace filter icon opens filters screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MarketplaceScreen()));
    await tester.pumpAndSettle();

    final filterFinder = find.byTooltip('Filters');
    expect(filterFinder, findsOneWidget);
    await tester.tap(filterFinder);
    await tester.pumpAndSettle();

    expect(find.byType(MarketplaceFiltersScreen), findsOneWidget);
  });

  testWidgets('Merchant shell renders 5 tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MerchantShell(debugUseLightweightTabs: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Listings'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Growth'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
  });

  testWidgets('Merchant home shows action buttons',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MerchantHomeScreen(autoLoad: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Listing'), findsOneWidget);
    expect(find.text('My Listings'), findsOneWidget);
    expect(find.text('View Orders'), findsOneWidget);
    expect(find.text('Chat Admin'), findsOneWidget);
    expect(find.text('Leaderboards'), findsOneWidget);
  });

  testWidgets('Buyer shell renders 5 tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BuyerShell(debugUseLightweightTabs: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Marketplace'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('Buyer home shows quick actions', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BuyerHomeScreen(autoLoad: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Browse Marketplace'), findsOneWidget);
    expect(find.text('My Orders'), findsOneWidget);
    expect(find.text('Chat Admin'), findsOneWidget);
    expect(find.text('Track Order'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Apply for Role'), findsOneWidget);
  });

  testWidgets('Admin shell renders 5 tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminShell(debugUseLightweightTabs: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Operations'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Driver shell renders 5 tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DriverShell(debugUseLightweightTabs: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Jobs'), findsOneWidget);
    expect(find.text('Earnings'), findsOneWidget);
    expect(find.text('MoneyBox'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
  });

  testWidgets('Inspector shell renders 5 tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InspectorShell(debugUseLightweightTabs: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('Earnings'), findsOneWidget);
    expect(find.text('MoneyBox'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
  });

  testWidgets('Admin overview renders quick actions',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminOverviewScreen(autoLoad: false),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Seed Nationwide'), findsOneWidget);
    expect(find.text('Seed Leaderboards'), findsOneWidget);
    expect(find.text('Run Notify Queue Demo'), findsOneWidget);
    expect(find.text('Toggle Autopilot'), findsOneWidget);
  });
}
