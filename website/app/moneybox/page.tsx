import { FeeTable } from '../../components/fee-table';

export default function MoneyboxPage() {
  return (
    <div className="space-y-8">
      <section>
        <h1 className="section-title">MoneyBox</h1>
        <p className="section-subtitle">Tiered lock savings with transparent bonus and early withdrawal penalties.</p>
      </section>

      <FeeTable
        title="Tier Structure"
        rows={[
          { item: 'Tier 1', value: '30 days, 0% bonus' },
          { item: 'Tier 2', value: '120 days, 3% bonus' },
          { item: 'Tier 3', value: '210 days, 8% bonus' },
          { item: 'Tier 4', value: '330 days, 15% bonus' }
        ]}
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <FeeTable
          title="Autosave Rules"
          rows={[
            { item: 'Eligible roles', value: 'Merchant, Driver, Inspector' },
            { item: 'Autosave range', value: '1% to 30%' },
            { item: 'Source credits', value: 'Role earnings and incentive credits' },
            { item: 'Maturity payout', value: 'Principal + tier bonus' }
          ]}
        />
        <FeeTable
          title="Penalty Bands"
          rows={[
            { item: 'First third of lock', value: '7%' },
            { item: 'Second third of lock', value: '5%' },
            { item: 'Final third of lock', value: '2%' },
            { item: 'At maturity', value: '0%' }
          ]}
        />
      </div>
    </div>
  );
}
