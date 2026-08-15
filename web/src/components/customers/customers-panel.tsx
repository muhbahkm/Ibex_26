'use client';

import { useMemo, useState } from 'react';

type Row = Record<string, unknown>;
type Props = { rows: Row[]; onOpen: (id: unknown) => void };

type CustomerGroup = {
  customerId: string;
  displayName: string;
  phone: string;
  lastTransactionAt: string | null;
  balances: Record<string, number>;
};

function formatNumber(value: unknown) {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(Number(value ?? 0));
}

function formatDate(value: unknown) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('ar-YE', { dateStyle: 'medium' }).format(new Date(String(value)));
}

export function CustomersPanel({ rows, onOpen }: Props) {
  const [search, setSearch] = useState('');
  const [onlyOutstanding, setOnlyOutstanding] = useState(false);

  const customers = useMemo(() => {
    const grouped = new Map<string, CustomerGroup>();
    for (const row of rows) {
      const customerId = String(row.customer_id ?? '');
      if (!customerId) continue;
      const existing = grouped.get(customerId) ?? {
        customerId,
        displayName: String(row.display_name ?? 'بدون اسم'),
        phone: String(row.phone ?? ''),
        lastTransactionAt: row.last_transaction_at ? String(row.last_transaction_at) : null,
        balances: {},
      };
      const currency = String(row.currency ?? '');
      if (currency) existing.balances[currency] = Number(row.balance ?? 0);
      if (row.last_transaction_at) {
        const candidate = String(row.last_transaction_at);
        if (!existing.lastTransactionAt || candidate > existing.lastTransactionAt) existing.lastTransactionAt = candidate;
      }
      grouped.set(customerId, existing);
    }
    return Array.from(grouped.values()).sort((a, b) => (b.lastTransactionAt ?? '').localeCompare(a.lastTransactionAt ?? ''));
  }, [rows]);

  const filtered = useMemo(() => {
    const query = search.trim().toLocaleLowerCase('ar');
    return customers.filter((customer) => {
      if (onlyOutstanding && !Object.values(customer.balances).some((balance) => balance > 0)) return false;
      if (!query) return true;
      return `${customer.displayName} ${customer.phone}`.toLocaleLowerCase('ar').includes(query);
    });
  }, [customers, search, onlyOutstanding]);

  const outstandingCount = useMemo(() => customers.filter((customer) => Object.values(customer.balances).some((balance) => balance > 0)).length, [customers]);

  return <div className="detail-stack">
    <div className="surface">
      <div className="surface-head"><div><strong>دليل العملاء</strong><p>كل عميل يظهر مرة واحدة، وأرصدته مفصولة داخل نفس السجل.</p></div><span className="count-pill">{filtered.length} عميل</span></div>
      <div className="statement-filters">
        <label><span>بحث</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="اسم العميل أو الهاتف…" /></label>
        <label><span>نوع الحساب</span><select value={onlyOutstanding ? 'outstanding' : 'all'} onChange={(event) => setOnlyOutstanding(event.target.value === 'outstanding')}><option value="all">كل العملاء</option><option value="outstanding">عليهم أرصدة فقط</option></select></label>
      </div>
      <div className="inline-notice">{customers.length} عميل مسجل · {outstandingCount} عميل لديه رصيد موجب في عملة واحدة على الأقل.</div>
    </div>

    <div className="surface"><div className="surface-head"><div><strong>الحسابات</strong><p>افتح العميل للتحصيل أو كشف الحساب أو مراجعة حركة دفتره.</p></div></div><div className="data-list">
      {filtered.length === 0 ? <div className="empty-state"><strong>لا يوجد عميل مطابق للفلتر.</strong></div> : filtered.map((customer) => <button className="data-row" onClick={() => onOpen(customer.customerId)} key={customer.customerId}><div><b>{customer.displayName}</b><small>{customer.phone || 'بدون رقم هاتف'} · آخر حركة {formatDate(customer.lastTransactionAt)}</small></div><div className="row-meta"><b>{(['YER','SAR','USD'] as const).filter((code) => customer.balances[code] !== undefined).map((code) => `${formatNumber(customer.balances[code])} ${code}`).join(' · ') || 'لا رصيد'}</b><small>الأرصدة منفصلة حسب العملة</small></div></button>)}
    </div></div>
  </div>;
}
