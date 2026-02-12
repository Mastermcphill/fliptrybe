import Link from 'next/link';
import { FeeTable } from '../components/fee-table';
import { FlowTimeline } from '../components/flow-timeline';
import { RoleEarningsTeaser } from '../components/role-earnings-teaser';

const roleCards = [
  {
    href: '/merchants',
    title: 'Merchants',
    text: 'List products, close sales, and track escrow-backed settlements.'
  },
  {
    href: '/drivers',
    title: 'Drivers',
    text: 'Accept verified delivery jobs and confirm handoffs with delivery codes.'
  },
  {
    href: '/inspectors',
    title: 'Inspectors',
    text: 'Handle booking requests, record reports, and get paid transparently.'
  }
];

export default function HomePage() {
  return (
    <div className="space-y-10">
      <section className="rounded-2xl bg-gradient-to-r from-brand-900 to-brand-700 p-8 text-white">
        <p className="text-xs font-semibold uppercase tracking-[0.18em]">FlipTrybe</p>
        <h1 className="mt-2 text-3xl font-black md:text-4xl">Trusted Commerce Flow for Nigeria</h1>
        <p className="mt-3 max-w-3xl text-sm text-cyan-100">
          Buyers, merchants, drivers, and inspectors run on one escrow-backed transaction timeline with clear earnings and delivery proof.
        </p>
        <div className="mt-6 flex flex-wrap gap-3">
          <Link href="/how-it-works" className="rounded-lg bg-white px-4 py-2 text-sm font-bold text-brand-900">How It Works</Link>
          <Link href="/moneybox" className="rounded-lg border border-cyan-200 px-4 py-2 text-sm font-bold text-white">MoneyBox Rules</Link>
        </div>
      </section>

      <section>
        <h2 className="section-title">Choose Your Mode</h2>
        <p className="section-subtitle">Each role has a clear workflow, fee logic, and compliance gates.</p>
        <div className="mt-5 grid gap-4 md:grid-cols-3">
          {roleCards.map((card) => (
            <Link key={card.href} href={card.href} className="card hover:border-brand-500">
              <h3 className="text-lg font-bold text-slate-900">{card.title}</h3>
              <p className="mt-2 text-sm text-slate-600">{card.text}</p>
            </Link>
          ))}
        </div>
      </section>

      <FlowTimeline
        title="Transaction Timeline"
        steps={[
          'Listing created and availability confirmed.',
          'Buyer pays and escrow holds the transaction total.',
          'Optional inspection booking and report submission.',
          'Driver pickup and dropoff confirmations with delivery code.',
          'Escrow release, wallet credit, and full audit trail.'
        ]}
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <RoleEarningsTeaser
          title="Merchant Example"
          monthlyGross="\u20A61,500,000"
          monthlyNet="\u20A61,500,000 + top-tier incentive"
          note="Merchant base proceeds remain intact. Platform fee is charged on top of base price."
        />
        <FeeTable
          title="Core Platform Rules"
          rows={[
            { item: 'Merchant platform fee', value: 'Default 3% on top of base price' },
            { item: 'Driver commission', value: '10% of delivery fee' },
            { item: 'Inspector commission', value: '10% of inspection fee' },
            { item: 'Driver/Inspector instant withdrawal', value: '1%' },
            { item: 'Merchant withdrawal', value: '0%' }
          ]}
        />
      </div>
    </div>
  );
}
