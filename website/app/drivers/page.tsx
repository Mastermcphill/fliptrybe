import { FeeTable } from '../../components/fee-table';
import { RoleEarningsTeaser } from '../../components/role-earnings-teaser';

export default function DriversPage() {
  return (
    <div className="space-y-8">
      <section>
        <h1 className="section-title">For Drivers</h1>
        <p className="section-subtitle">Accept verified jobs, complete delivery code confirmations, and track net earnings.</p>
      </section>

      <RoleEarningsTeaser
        title="Driver Monthly Example"
        monthlyGross="\u20A6390,000"
        monthlyNet="\u20A6351,000 before withdrawal speed choice"
        note="Commission is 10% of delivery fees. Instant withdrawal adds 1% fee; standard withdrawal is 0%."
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <FeeTable
          title="Driver Fee Logic"
          rows={[
            { item: 'Delivery fee gross', value: 'Based on accepted jobs' },
            { item: 'Platform commission', value: '10%' },
            { item: 'Net before withdrawal', value: 'Gross - 10%' },
            { item: 'Instant withdrawal', value: '1%' },
            { item: 'Standard withdrawal', value: '0%' }
          ]}
        />
        <FeeTable
          title="Driver Workflow"
          rows={[
            { item: 'Job assignment', value: 'In-app + optional SMS/WhatsApp alert' },
            { item: 'Pickup confirmation', value: 'Driver confirms pickup step' },
            { item: 'Dropoff confirmation', value: 'Delivery code/QR verification' },
            { item: 'Payout timing', value: 'After successful completion and checks' }
          ]}
        />
      </div>
    </div>
  );
}
