import { FeeTable } from '../../components/fee-table';

export default function TrustSafetyPage() {
  return (
    <div className="space-y-8">
      <section>
        <h1 className="section-title">Trust and Safety</h1>
        <p className="section-subtitle">Escrow controls, verified roles, and auditable delivery states reduce fraud risk.</p>
      </section>

      <div className="grid gap-4 lg:grid-cols-2">
        <FeeTable
          title="Transaction Protection"
          rows={[
            { item: 'Escrow holding', value: 'Funds held until delivery confirmation rules pass' },
            { item: 'Availability timeout', value: 'Auto refund if seller is unresponsive' },
            { item: 'Delivery proof', value: 'Code/QR and timeline checkpoints' },
            { item: 'Dispute traceability', value: 'Event history retained per order' }
          ]}
        />
        <FeeTable
          title="Account Controls"
          rows={[
            { item: 'Role requests', value: 'Admin review before sensitive role elevation' },
            { item: 'Email verification', value: 'Required for money-moving actions' },
            { item: 'KYC checks', value: 'Applied to payouts and higher trust actions' },
            { item: 'Admin support', value: 'Direct support chat for escalations' }
          ]}
        />
      </div>
    </div>
  );
}
