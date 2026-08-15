import type { Metadata } from 'next';
import './globals.css';
import './manual-sale.css';

export const metadata: Metadata = {
  title: 'باحكم | المساعد التشغيلي',
  description: 'واجهة تشغيل ذكية لبيانات باحكم للعسل',
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ar" dir="rtl"><body>{children}</body></html>;
}
