interface FlowTimelineProps {
  title: string;
  steps: string[];
}

export function FlowTimeline({ title, steps }: FlowTimelineProps) {
  return (
    <section className="card">
      <h3 className="text-xl font-bold text-slate-900">{title}</h3>
      <ol className="mt-4 space-y-3">
        {steps.map((step, index) => (
          <li key={step} className="flex gap-3">
            <span className="mt-1 inline-flex h-6 w-6 items-center justify-center rounded-full bg-brand-500 text-xs font-bold text-white">
              {index + 1}
            </span>
            <span className="text-sm text-slate-700">{step}</span>
          </li>
        ))}
      </ol>
    </section>
  );
}
