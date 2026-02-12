import { FeeTable } from '../../components/fee-table';
import { RoleEarningsTeaser } from '../../components/role-earnings-teaser';

export default function MerchantsPage() {
  return (
    <div className="space-y-8">
      <section>
        <h1 className="section-title">For Merchants</h1>
        <p className="section-subtitle">Run listings, orders, payouts, and growth from one operations dashboard.</p>
      </section>

      <RoleEarningsTeaser
        title="Merchant Economics"
        monthlyGross="\u20A61,500,000 base revenue"
        monthlyNet="\u20A61,500,000 + top-tier share"
        note="Platform fee is charged on top of base listing price. Top-tier merchants receive 11/13 of platform fee."
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <FeeTable
          title="Merchant Revenue Rules"
          rows={[
            { item: 'Buyer payment', value: 'Base price + platform fee' },
            { item: 'Merchant base payout', value: '100% of base listing price' },
            { item: 'Platform fee', value: 'Default 3%' },
            { item: 'Top-tier incentive', value: '11/13 of platform fee to merchant' },
            { item: 'Merchant withdrawal fee', value: '0%' }
          ]}
        />
        <FeeTable
          title="Merchant Controls"
          rows={[
            { item: 'Required for listing create', value: 'Verified email' },
            { item: 'Role upgrade', value: 'Admin approval flow' },
            { item: 'Support channel', value: 'Admin support chat thread' },
            { item: 'Growth tools', value: 'Leaderboards + followers + KPI tracking' }
          ]}
        />
      </div>
    </div>
  );
}
