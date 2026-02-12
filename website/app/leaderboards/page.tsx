import { FeeTable } from '../../components/fee-table';

export default function LeaderboardsPage() {
  return (
    <div className="space-y-8">
      <section>
        <h1 className="section-title">Leaderboards</h1>
        <p className="section-subtitle">Nationwide and state-level ranking to reward reliability and service quality.</p>
      </section>

      <FeeTable
        title="Ranking Inputs"
        rows={[
          { item: 'Successful deliveries', value: 'Higher completion improves score' },
          { item: 'Order quality', value: 'Low dispute and cancellation rate' },
          { item: 'Rating signals', value: 'Average rating + count weighting' },
          { item: 'Sales strength', value: 'Sustained transaction performance' }
        ]}
      />

      <FeeTable
        title="Why Ranking Matters"
        rows={[
          { item: 'Merchant visibility', value: 'Stronger placement in growth views' },
          { item: 'Top-tier path', value: 'Eligibility for platform fee incentive split' },
          { item: 'Trust signal', value: 'Faster buyer confidence and conversion' }
        ]}
      />
    </div>
  );
}
