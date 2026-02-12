interface FeeTableProps {
  title: string;
  rows: Array<{ item: string; value: string }>;
}

export function FeeTable({ title, rows }: FeeTableProps) {
  return (
    <section className="card">
      <h3 className="text-xl font-bold text-slate-900">{title}</h3>
      <table className="mt-4 w-full border-collapse text-sm">
        <thead>
          <tr className="bg-slate-100 text-left text-slate-800">
            <th className="border border-slate-200 px-3 py-2">Item</th>
            <th className="border border-slate-200 px-3 py-2">Value</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.item}>
              <td className="border border-slate-200 px-3 py-2">{row.item}</td>
              <td className="border border-slate-200 px-3 py-2">{row.value}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
