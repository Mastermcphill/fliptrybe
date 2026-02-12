import Link from 'next/link';

const links = [
  { href: '/', label: 'Home' },
  { href: '/how-it-works', label: 'How It Works' },
  { href: '/merchants', label: 'Merchants' },
  { href: '/drivers', label: 'Drivers' },
  { href: '/inspectors', label: 'Inspectors' },
  { href: '/moneybox', label: 'MoneyBox' },
  { href: '/leaderboards', label: 'Leaderboards' },
  { href: '/trust-safety', label: 'Trust & Safety' },
  { href: '/contact', label: 'Contact' },
];

export function Navbar() {
  return (
    <header className="border-b border-slate-200 bg-white/95">
      <div className="site-container flex items-center justify-between py-4">
        <Link href="/" className="text-lg font-black text-slate-900">FlipTrybe</Link>
        <nav className="hidden gap-4 text-sm font-semibold text-slate-700 md:flex">
          {links.map((item) => (
            <Link key={item.href} href={item.href} className="hover:text-brand-700">
              {item.label}
            </Link>
          ))}
        </nav>
      </div>
    </header>
  );
}
