'use client';

import { useMemo, useState } from 'react';

type Row = Record<string, unknown>;
type Props = { rows: Row[]; onOpen: (id: unknown) => void };

function formatNumber(value: unknown) {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(Number(value ?? 0));
}

function formatDate(value: unknown) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('ar-YE', { dateStyle: 'medium' }).format(new Date(String(value)));
}

function paymentLabel(value: unknown) {
  const status = String(value ?? '');
  if (status === 'cash') return 'نقد';
  if (status === 'credit') return 'آجل';
  if (status === 'partial') return 'جزئي';
  return status || '—';
}

export function TransactionsPanel({ rows, onOpen }: Props) {
  const [search, setSearch] = useState('');
  const [currency, setCurrency] = useState('');
  const [paymentStatus, setPaymentStatus] = useState('');
  const [transactionType, setTransactionType] = useState('');

  const types = useMemo(() => Array.from(new Set(rows.map((row) => String(row.transaction_type ?? '')).filter(Boolean))), [rows]);
  const filtered = useMemo(() => {
    const query = search.trim().toLocaleLowerCase('ar');
    return rows.filter((row) => {
      if (currency && String(row.currency) !== currency) return false;
      if (paymentStatus && String(row.payment_status) !== paymentStatus) return false;
      if (transactionType && String(row.transaction_type) !== transactionType) return false;
      if (!query) return true;
      return [row.transaction_no, row.customer_name, row.customer_phone, row.notes]
        .some((value) => String(value ?? '').toLocaleLowerCase('ar').includes(query));
    });
  }, [rows, search, currency, paymentStatus, transactionType]);

  const selectedCurrency = currency || null;
  const summary = useMemo(() => selectedCurrency ? filtered.reduce<{ total: number; paid: number; remaining: number; profit: number }>((sum, row) => ({
    total: sum.total + Number(row.total_amount ?? 0),
    paid: sum.paid + Number(row.paid_amount ?? 0),
    remaining: sum.remaining + Number(row.remaining_amount ?? 0),
    profit: sum.profit + Number(row.estimated_profit ?? 0),
  }), { total: 0, paid: 0, remaining: 0, profit: 0 }) : null, [filtered, selectedCurrency]);

  function reset() {
    setSearch('');
    setCurrency('');
    setPaymentStatus('');
    setTransactionType('');
  }

  return <div className="detail-stack">
    <div className="surface">
      <div className="surface-head"><div><strong>تصفية العمليات</strong><p>ابحث وحدد العملة وحالة السداد ونوع الحركة.</p></div><span className="count-pill">{filtered.length} من {rows.length}</span></div>
      <div className="statement-filters">
        <label><span>بحث</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="رقم العملية أو العميل…" /></label>
        <label><span>العملة</span><select value={currency} onChange={(event) => setCurrency(event.target.value)}><option value="">كل العملات</option><option value="YER">YER</option><option value="SAR">SAR</option><option value="USD">USD</option></select></label>
        <label><span>السداد</span><select value={paymentStatus} onChange={(event) => setPaymentStatus(event.target.value)}><option value="">الكل</option><option value="cash">نقد</option><option value="credit">آجل</option><option value="partial">جزئي</option></select></label>
        <label><span>النوع</span><select value={transactionType} onChange={(event) => setTransactionType(event.target.value)}><option value="">كل الأنواع</option>{types.map((type) => <option key={type} value={type}>{type}</option>)}</select></label>
        <button type="button" onClick={reset}>إعادة ضبط</button>
      </div>
      {!selectedCurrency && <div className="inline-notice">لا يتم جمع قيم العمليات بين العملات المختلفة. اختر عملة واحدة لعرض المجاميع المالية.</div>}
    </div>

    {summary && <div className="balance-grid">
      <div className="balance-card"><span>الإجمالي</span><b>{formatNumber(summary.total)}</b><small>{selectedCurrency}</small></div>
      <div className="balance-card"><span>المدفوع</span><b>{formatNumber(summary.paid)}</b><small>{selectedCurrency}</small></div>
      <div className="balance-card"><span>المتبقي</span><b>{formatNumber(summary.remaining)}</b><small>{selectedCurrency}</small></div>
      <div className="balance-card"><span>الربح التقديري</span><b>{formatNumber(summary.profit)}</b><small>{selectedCurrency}</small></div>
    </div>}

    <div className="surface"><div className="surface-head"><div><strong>سجل العمليات</strong><p>اضغط على أي حركة لفتح البنود والتفاصيل المالية.</p></div><span className="count-pill">{filtered.length} عملية</span></div><div className="data-list">
      {filtered.length === 0 ? <div className="empty-state"><strong>لا توجد عمليات مطابقة للفلاتر.</strong></div> : filtered.map((row) => <button className="data-row" onClick={() => onOpen(row.id)} key={String(row.id)}><div><b>{String(row.transaction_no)}</b><small>{String(row.customer_name ?? 'بدون طرف')} · {formatDate(row.transaction_datetime)}</small></div><div className="row-meta"><b>{formatNumber(row.total_amount)} {String(row.currency)}</b><small>{paymentLabel(row.payment_status)} · ربح {formatNumber(row.estimated_profit)}</small></div></button>)}
    </div></div>
  </div>;
}
