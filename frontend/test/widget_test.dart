import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fliptrybe/screens/landing_screen.dart';
import 'package:fliptrybe/screens/role_signup_screen.dart';
import 'package:fliptrybe/screens/marketplace_screen.dart';
import 'package:fliptrybe/screens/marketplace_filters_screen.dart';
import 'package:fliptrybe/screens/listing_detail_screen.dart';
import 'package:fliptrybe/screens/admin_overview_screen.dart';
import 'package:fliptrybe/screens/buyer_home_screen.dart';
import 'package:fliptrybe/screens/how_it_works/role_how_it_works_screen.dart';
import 'package:fliptrybe/screens/merchant_home_screen.dart';
import 'package:fliptrybe/screens/transaction/transaction_timeline_screen.dart';
import 'package:fliptrybe/widgets/transaction/transaction_timeline_step.dart';
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

  testWidgets('Merchant home opens How It Works screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MerchantHomeScreen(autoLoad: false),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.textContaining('How FlipTrybe Works');
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(finder, findsWidgets);
    await tester.tap(finder.first);
    await tester.pumpAndSettle();

    expect(find.byType(RoleHowItWorksScreen), findsOneWidget);
    expect(find.text('Merchant: How FlipTrybe Works'), findsOneWidget);
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
    expect(find.text('Growth'), findsOneWidget);
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
    expect(find.text('Growth'), findsOneWidget);
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

  testWidgets('Transaction timeline renders 5+ key steps',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TransactionTimelineScreen(
          orderId: 77,
          autoLoad: false,
          initialOrder: {
            'id': 77,
            'status': 'completed',
            'amount': 50000,
            'platform_fee': 1500,
            'delivery_fee': 2500,
            'escrow_status': 'released',
          },
          initialDelivery: {
            'pickup_confirmed_at': '2026-01-01T09:00:00Z',
            'dropoff_confirmed_at': '2026-01-01T12:00:00Z',
          },
          initialEvents: [
            {'event': 'availability_confirmed'},
            {'event': 'payment_captured', 'sms_sent': true},
            {'event': 'driver_assigned'},
            {'event': 'pickup_confirmed'},
            {'event': 'delivery_confirmed', 'notified_whatsapp': true},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Order Lifecycle'), findsOneWidget);
    expect(find.byType(TransactionTimelineStep), findsAtLeastNWidgets(1));
    expect(find.textContaining('Listing Created'), findsWidgets);
    await tester.scrollUntilVisible(
      find.textContaining('Wallet Credited'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Wallet Credited'), findsWidgets);
  });

  testWidgets('Transaction timeline does not overflow on small device',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: TransactionTimelineScreen(
          orderId: 55,
          autoLoad: false,
          initialOrder: {'id': 55, 'status': 'created'},
          initialEvents: [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
