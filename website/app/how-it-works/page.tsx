import { FlowTimeline } from '../../components/flow-timeline';
import { FeeTable } from '../../components/fee-table';

export default function HowItWorksPage() {
  return (
    <div className="space-y-8">
      <section>
        <h1 className="section-title">How FlipTrybe Works</h1>
        <p className="section-subtitle">Escrow, delivery proof, and role accountability from listing to payout.</p>
      </section>

      <FlowTimeline
        title="Buyer Journey"
        steps={[
          'Browse listings and request availability.',
          'Pay once seller confirms; escrow secures transaction value.',
          'Optional inspector booking for quality validation.',
          'Driver completes pickup/dropoff using delivery code flow.',
          'Buyer confirms receipt and escrow releases payouts.'
        ]}
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <FeeTable
          title="Escrow and Delivery Logic"
          rows={[
            { item: 'Availability timeout', value: 'Auto refund if seller does not respond in 2 hours' },
            { item: 'Delivery proof', value: 'Code/QR confirmations + status timeline' },
            { item: 'Escrow states', value: 'Held -> Released or Refunded' },
            { item: 'Notifications', value: 'In-app + SMS/WhatsApp when enabled' }
          ]}
        />
        <FeeTable
          title="Trust Controls"
          rows={[
            { item: 'Role gating', value: 'Admin approval for restricted roles' },
            { item: 'Email verification', value: 'Required for sensitive actions' },
            { item: 'KYC', value: 'Applied to withdrawal and tier upgrades' },
            { item: 'Dispute trail', value: 'Full transaction events stored in timeline' }
          ]}
        />
      </div>
    </div>
  );
}
