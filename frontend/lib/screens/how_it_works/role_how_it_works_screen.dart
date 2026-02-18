import 'package:flutter/material.dart';

import '../../widgets/how_it_works/how_it_works_fee_table.dart';
import '../../widgets/how_it_works/how_it_works_section.dart';
import '../../widgets/how_it_works/how_it_works_timeline_step.dart';

class RoleHowItWorksScreen extends StatelessWidget {
  const RoleHowItWorksScreen({super.key, required this.role});

  final String role;

  String _title() {
    switch (role.toLowerCase()) {
      case 'merchant':
        return 'Merchant: How FlipTrybe Works';
      case 'driver':
        return 'Driver: How FlipTrybe Works';
      case 'inspector':
        return 'Inspector: How FlipTrybe Works';
      default:
        return 'How FlipTrybe Works';
    }
  }

  List<Widget> _merchantSections() {
    return [
      HowItWorksSection(
        title: '1. Creating Listings',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HowItWorksTimelineStep(
              title: 'Create listing details',
              description:
                  'Add title, price, location and product photos from your merchant dashboard.',
            ),
            HowItWorksTimelineStep(
              title: 'Listing limits',
              description:
                  'Current app listing limits apply. Platform commission is added on sale; your base item price remains your expected revenue base.',
            ),
          ],
        ),
      ),
      HowItWorksSection(
        title: '2. Buyer Availability Check',
        child: const Text(
          'When a buyer requests availability, merchants have 2 hours to confirm. No response within the window triggers automatic buyer refund.',
        ),
      ),
      HowItWorksSection(
        title: '3. Buyer Payment and Escrow',
        child: const Text(
          'When Paystack is enabled, buyer payment enters escrow. Merchants do not need manual fund protection steps.',
        ),
      ),
      HowItWorksSection(
        title: '4. Optional Inspection',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Buyer can request inspection before completion.'),
            SizedBox(height: 8),
            Text(
              'Inspector appointment details, photos and notes are logged in-app. Inspection fee pays out with a 10% platform commission.',
            ),
          ],
        ),
      ),
      HowItWorksSection(
        title: '5. Delivery',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Driver accepts delivery, confirms pickup and dropoff.'),
            SizedBox(height: 8),
            Text('Delivery code and optional QR are used to verify handoff.'),
            SizedBox(height: 8),
            Text('Delivery fee pays out with a 10% platform commission.'),
          ],
        ),
      ),
      HowItWorksSection(
        title: '6. Escrow Release',
        child: const Text(
          'Escrow releases after delivery confirmation and required verification checks. Merchant payout is then credited automatically.',
        ),
      ),
      HowItWorksSection(
        title: '7. Commission Logic (Merchant)',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Merchant receives base price.'),
            Text('Platform receives platform fee (default 3%).'),
            Text(
                'Top-tier merchant receives 11/13 of platform fee; platform keeps 2/13.'),
            SizedBox(height: 10),
            HowItWorksFeeTable(
              headers: ['Metric', 'Value'],
              rows: [
                ['Orders/month', '30'],
                ['Average item price', '₦50,000'],
                ['Gross base revenue', '₦1,500,000'],
                ['Platform fee (3%)', '₦45,000'],
                ['Top-tier incentive (11/13)', '₦38,076.92'],
                ['Final merchant earnings', '₦1,538,076.92'],
              ],
            ),
          ],
        ),
      ),
      HowItWorksSection(
        title: '8. Withdrawal Fees',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Standard withdrawal fee: 0%.'),
            Text('Phone verification required.'),
            Text('KYC may be required by endpoint policy.'),
          ],
        ),
      ),
      HowItWorksSection(
        title: '9. MoneyBox',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tier 1: 30 days - 0% bonus'),
            Text('Tier 2: 120 days - 3% bonus'),
            Text('Tier 3: 210 days - 8% bonus'),
            Text('Tier 4: 330 days - 15% bonus'),
            SizedBox(height: 8),
            Text('Autosave range: 1% - 30% on eligible credits.'),
            Text(
                'Eligible credits: top_tier_incentive, delivery_fee, inspection_fee, commission_credit.'),
            SizedBox(height: 8),
            Text(
                'Penalty bands: first third 7%, second third 5%, final third 2%, maturity 0%.'),
            SizedBox(height: 10),
            HowItWorksFeeTable(
              headers: ['MoneyBox Example', 'Amount'],
              rows: [
                ['10% autosave over 3 months', '₦153,807.69'],
                ['Tier 2 maturity (3%)', '₦158,421.92'],
                ['Tier 4 maturity (15%)', '₦176,878.84'],
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _driverSections() {
    return [
      HowItWorksSection(
        title: '1. Job Assignment',
        child: const Text(
          'Driver receives jobs in-app and by SMS/WhatsApp when messaging integrations are enabled.',
        ),
      ),
      HowItWorksSection(
        title: '2. Pickup',
        child: const Text('Confirm pickup in app before moving to dropoff.'),
      ),
      HowItWorksSection(
        title: '3. Delivery',
        child: const Text(
          'Enter delivery code at handoff. Optional QR scan can also be used for verification.',
        ),
      ),
      HowItWorksSection(
        title: '4. Payout',
        child: const Text(
          'Delivery fee is credited to wallet after 10% platform commission is deducted.',
        ),
      ),
      HowItWorksSection(
        title: '5. Withdrawal',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Instant withdrawal fee: 1%'),
            Text('Standard withdrawal fee: 0%'),
          ],
        ),
      ),
      HowItWorksSection(
        title: '6. Earnings Table',
        child: const HowItWorksFeeTable(
          headers: ['Metric', 'Value'],
          rows: [
            ['Delivery fee', '₦2,500'],
            ['Deliveries/day', '6'],
            ['Work days/month', '26'],
            ['Gross monthly', '₦390,000'],
            ['Platform commission (10%)', '₦39,000'],
            ['Net earnings', '₦351,000'],
            ['Instant withdraw (1%)', '₦347,490'],
            ['Standard withdraw (0%)', '₦351,000'],
          ],
        ),
      ),
      HowItWorksSection(
        title: '7. MoneyBox',
        child: const HowItWorksFeeTable(
          headers: ['Scenario', 'Amount'],
          rows: [
            ['Autosave 10% monthly net', '₦35,100'],
            ['Tier 2 projected maturity', '₦36,153'],
            ['Tier 4 projected maturity', '₦40,365'],
          ],
        ),
      ),
    ];
  }

  List<Widget> _inspectorSections() {
    return [
      HowItWorksSection(
        title: '1. Booking Received',
        child: const Text(
          'Inspection booking arrives in-app and can trigger SMS/WhatsApp alerts when enabled.',
        ),
      ),
      HowItWorksSection(
        title: '2. Appointment Scheduling',
        child: const Text(
          'Inspector logs appointment time and location in the app timeline.',
        ),
      ),
      HowItWorksSection(
        title: '3. Identity & Security',
        child: const Text(
          'Seller sees inspector name, verification status and appointment details.',
        ),
      ),
      HowItWorksSection(
        title: '4. Inspection Execution',
        child: const Text(
          'Inspector uploads photos and notes for traceable inspection records.',
        ),
      ),
      HowItWorksSection(
        title: '5. Payout',
        child: const Text(
          'Inspection fee pays out after 10% platform commission is deducted.',
        ),
      ),
      HowItWorksSection(
        title: '6. Withdrawal',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Instant withdrawal fee: 1%'),
            Text('Standard withdrawal fee: 0%'),
          ],
        ),
      ),
      HowItWorksSection(
        title: '7. Earnings Table',
        child: const HowItWorksFeeTable(
          headers: ['Metric', 'Value'],
          rows: [
            ['Inspection fee', '₦5,000'],
            ['Inspections/day', '3'],
            ['Work days/month', '24'],
            ['Gross monthly', '₦360,000'],
            ['Platform commission (10%)', '₦36,000'],
            ['Net earnings', '₦324,000'],
            ['Instant withdraw (1%)', '₦320,760'],
            ['Standard withdraw (0%)', '₦324,000'],
          ],
        ),
      ),
      HowItWorksSection(
        title: '8. MoneyBox',
        child: const HowItWorksFeeTable(
          headers: ['Scenario', 'Amount'],
          rows: [
            ['Autosave 10% monthly net', '₦32,400'],
            ['Tier 2 projected maturity', '₦33,372'],
            ['Tier 4 projected maturity', '₦37,260'],
          ],
        ),
      ),
    ];
  }

  List<Widget> _sectionsByRole() {
    switch (role.toLowerCase()) {
      case 'merchant':
        return _merchantSections();
      case 'driver':
        return _driverSections();
      case 'inspector':
        return _inspectorSections();
      default:
        return const [
          HowItWorksSection(
            title: 'How FlipTrybe Works',
            child: Text('Role details are not available yet.'),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _sectionsByRole(),
      ),
    );
  }
}
