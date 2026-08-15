'use client';

import { useMemo, useState } from 'react';

type Row = Record<string, unknown>;
type Props = { initialRows: Row[]; onOpenCustomer: (id: unknown) => void };

function formatNumber(value: unknown) {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(Number(value ?? 0));
}

function formatDate(value: unknown) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('ar-YE', { dateStyle: 'medium' }).format(new Date(String(value)));
}

export function DebtsPanel({ initialRows, onOpenCustomer }: Props) {
  const [rows, setRows] = useState<Row[]>(initialRows);
  const [days, setDays] = useState(30);
  const [currency, setCurrency] = useState('');
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const filtered = useMemo(() => {
    const query = search.trim().toLocaleLowerCase('ar');
    return rows.filter((row) => {
      if (currency && String(row.currency) !== currency) return false;
      if (!query) return true;
      return [row.display_name, row.phone].some((value) => String(value ?? '').toLocaleLowerCase('ar').includes(query));
    });
  }, [rows, currency, search]);

  const currencyTotal = useMemo(() => currency ? filtered.reduce((sum, row) => sum + Number(row.balance ?? 0), 0) : null, [filtered, currency]);

  async function changeAge(nextDays: number) {
    setDays(nextDays);
    setBusy(true);
    setError(null);
    try {
      const response = await fetch(`/api/workspace?section=debts&days=${nextDays}`);
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? 'DEBTS_READ_FAILED');
      setRows(Array.isArray(body.rows) ? body.rows : []);
    } catch {
      setError('تعذر تحديث قائمة الديون للفترة المحددة.');
    } finally {
      setBusy(false);
    }
  }

  return <div className="detail-stack">
    <div className="surface">
      <div className="surface-head"><div><strong>أولوية التحصيل</strong><p>غيّر حد التأخر وابحث عن العميل أو افصل القائمة حسب العملة.</p></div><span className="count-pill danger">{filtered.length} متابعة</span></div>
      <div className="statement-filters">
        <label><span>متأخر منذ</span><select value={days} disabled={busy} onChange={(event) => void changeAge(Number(event.target.value))}><option value={7}>7 أيام</option><option value={14}>14 يومًا</option><option value={30}>30 يومًا</option><option value={60}>60 يومًا</option><option value={90}>90 يومًا</option></select></label>
        <label><span>العملة</span><select value={currency} onChange={(event) => setCurrency(event.target.value)}><option value="">كل العملات</option><option value="YER">YER</option><option value="SAR">SAR</option><option value="USD">USD</option></select></label>
        <label><span>بحث</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="اسم العميل أو الهاتف…" /></label>
      </div>
      {busy && <div className="inline-notice">جارٍ تحديث قائمة المتابعة…</div>}
      {error && <div className="inline-notice">{error}</div>}
      {!currency && <div className="inline-notice">الأرصدة تبقى مفصولة حسب العملة؛ لا يتم جمع العملات المختلفة.</div>}
    </div>

    {currency && <div className="balance-grid"><div className="balance-card"><span>إجمالي المتابعة</span><b>{formatNumber(currencyTotal)}</b><small>{currency}</small></div><div className="balance-card"><span>عدد الحسابات</span><b>{filtered.length}</b><small>متأخرة أكثر من {days} يومًا</small></div></div>}

    <div className="surface"><div className="surface-head"><div><strong>الديون المتأخرة</strong><p>مرتبة من البيانات الفعلية؛ افتح العميل للتحصيل أو كشف الحساب.</p></div></div><div className="data-list">
      {filtered.length === 0 ? <div className="empty-state"><strong>لا توجد ديون مطابقة للمعايير الحالية.</strong></div> : filtered.map((row) => <button className="data-row" onClick={() => onOpenCustomer(row.customer_id)} key={`${row.customer_id}-${row.currency}`}><div><b>{String(row.display_name ?? 'عميل')}</b><small>{row.phone ? String(row.phone) : 'بدون رقم هاتف'} · آخر نشاط {formatDate(row.last_ledger_activity_at)}</small></div><div className="row-meta"><b>{formatNumber(row.balance)} {String(row.currency)}</b><small>{formatNumber(row.days_since_last_activity)} يوم دون حركة</small></div></button>)}
    </div></div>
  </div>;
}
