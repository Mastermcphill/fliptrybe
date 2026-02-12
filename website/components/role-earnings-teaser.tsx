interface RoleEarningsTeaserProps {
  title: string;
  monthlyGross: string;
  monthlyNet: string;
  note: string;
}

export function RoleEarningsTeaser({ title, monthlyGross, monthlyNet, note }: RoleEarningsTeaserProps) {
  return (
    <section className="card">
      <h3 className="text-xl font-bold text-slate-900">{title}</h3>
      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <div className="rounded-lg bg-slate-50 p-3">
          <p className="text-xs font-semibold uppercase text-slate-500">Monthly Gross</p>
          <p className="text-lg font-black text-slate-900">{monthlyGross}</p>
        </div>
        <div className="rounded-lg bg-slate-50 p-3">
          <p className="text-xs font-semibold uppercase text-slate-500">Monthly Net</p>
          <p className="text-lg font-black text-slate-900">{monthlyNet}</p>
        </div>
      </div>
      <p className="mt-3 text-sm text-slate-600">{note}</p>
    </section>
  );
}
