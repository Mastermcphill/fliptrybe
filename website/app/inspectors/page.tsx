import { FeeTable } from '../../components/fee-table';
import { RoleEarningsTeaser } from '../../components/role-earnings-teaser';

export default function InspectorsPage() {
  return (
    <div className="space-y-8">
      <section>
        <h1 className="section-title">For Inspectors</h1>
        <p className="section-subtitle">Manage inspections, upload reports, and get transparent net payouts.</p>
      </section>

      <RoleEarningsTeaser
        title="Inspector Monthly Example"
        monthlyGross="\u20A6360,000"
        monthlyNet="\u20A6324,000 before withdrawal speed choice"
        note="Inspection fee commission is 10%. Instant withdrawal is 1%; standard is 0%."
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <FeeTable
          title="Inspector Fee Logic"
          rows={[
            { item: 'Inspection fee gross', value: 'Based on completed inspections' },
            { item: 'Platform commission', value: '10%' },
            { item: 'Net before withdrawal', value: 'Gross - 10%' },
            { item: 'Instant withdrawal', value: '1%' },
            { item: 'Standard withdrawal', value: '0%' }
          ]}
        />
        <FeeTable
          title="Inspector Workflow"
          rows={[
            { item: 'Booking notification', value: 'In-app + optional SMS/WhatsApp' },
            { item: 'Appointment log', value: 'Date/time/location tracked in app' },
            { item: 'Inspection report', value: 'Photos + notes submission' },
            { item: 'Payout release', value: 'After validated completion' }
          ]}
        />
      </div>
    </div>
  );
}
