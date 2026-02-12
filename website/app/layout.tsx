import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import './globals.css';
import { Navbar } from '../components/navbar';
import { Footer } from '../components/footer';

export const metadata: Metadata = {
  title: 'FlipTrybe',
  description: 'Escrow-first commerce for buyers, merchants, drivers, and inspectors in Nigeria.'
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Navbar />
        <main className="site-container py-8">{children}</main>
        <Footer />
      </body>
    </html>
  );
}

