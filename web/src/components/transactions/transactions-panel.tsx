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

function transactionTypeLabel(value: unknown) {
  const type = String(value ?? '');
  if (type === 'sales_invoice') return 'فاتورة مبيعات';
  if (type === 'receipt_voucher') return 'سند قبض';
  if (type === 'payment_voucher') return 'سند صرف';
  if (type === 'purchase_invoice') return 'فاتورة مشتريات';
  if (type === 'simple_entry') return 'قيد';
  return type || 'عملية';
}

function isInteractiveRow(row: Row) {
  return typeof row.id === 'string' && row.id.length > 0 && typeof row.transaction_no === 'string' && row.transaction_no.length > 0;
}

export function TransactionsPanel({ rows, onOpen }: Props) {
  const [search, setSearch] = useState('');
  const [currency, setCurrency] = useState('');
  const [paymentStatus, setPaymentStatus] = useState('');
  const [transactionType, setTransactionType] = useState('');

  const safeRows = useMemo(() => rows.filter(isInteractiveRow), [rows]);
  const rejectedRows = rows.length - safeRows.length;
  const types = useMemo(() => Array.from(new Set(safeRows.map((row) => String(row.transaction_type ?? '')).filter(Boolean))), [safeRows]);

  const filtered = useMemo(() => {
    const query = search.trim().toLocaleLowerCase('ar');
    return safeRows.filter((row) => {
      if (currency && String(row.currency) !== currency) return false;
      if (paymentStatus && String(row.payment_status) !== paymentStatus) return false;
      if (transactionType && String(row.transaction_type) !== transactionType) return false;
      if (!query) return true;
      return [row.transaction_no, row.customer_name, row.customer_phone, row.notes]
        .some((value) => String(value ?? '').toLocaleLowerCase('ar').includes(query));
    });
  }, [safeRows, search, currency, paymentStatus, transactionType]);

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

  return <div className="detail-stack operational-register">
    <div className="surface filter-surface">
      <div className="surface-head compact-head">
        <div><strong>تصفية العمليات</strong><p>بحث سريع مع فصل النتائج والمجاميع حسب العملة.</p></div>
        <span className="count-pill">{filtered.length} من {safeRows.length}</span>
      </div>
      <div className="register-filters">
        <label className="filter-search"><span>بحث</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="رقم العملية، العميل أو الملاحظات…" /></label>
        <label><span>العملة</span><select value={currency} onChange={(event) => setCurrency(event.target.value)}><option value="">كل العملات</option><option value="YER">YER</option><option value="SAR">SAR</option><option value="USD">USD</option></select></label>
        <label><span>السداد</span><select value={paymentStatus} onChange={(event) => setPaymentStatus(event.target.value)}><option value="">الكل</option><option value="cash">نقد</option><option value="credit">آجل</option><option value="partial">جزئي</option></select></label>
        <label><span>النوع</span><select value={transactionType} onChange={(event) => setTransactionType(event.target.value)}><option value="">كل الأنواع</option>{types.map((type) => <option key={type} value={type}>{transactionTypeLabel(type)}</option>)}</select></label>
        <button className="filter-reset" type="button" onClick={reset}>مسح الفلاتر</button>
      </div>
      {rejectedRows > 0 && <div className="contract-alert">تم حجب {rejectedRows} سجل غير مكتمل لحماية واجهة التشغيل. أعد تحميل الصفحة؛ وإذا استمر التنبيه فهناك خلل في عقد البيانات.</div>}
    </div>

    {summary && <div className="balance-grid register-summary">
      <div className="balance-card"><span>إجمالي العمليات</span><b>{formatNumber(summary.total)}</b><small>{selectedCurrency}</small></div>
      <div className="balance-card"><span>المدفوع</span><b>{formatNumber(summary.paid)}</b><small>{selectedCurrency}</small></div>
      <div className="balance-card"><span>المتبقي</span><b>{formatNumber(summary.remaining)}</b><small>{selectedCurrency}</small></div>
      <div className="balance-card"><span>الربح التقديري</span><b>{formatNumber(summary.profit)}</b><small>{selectedCurrency}</small></div>
    </div>}

    <div className="surface register-surface">
      <div className="surface-head compact-head"><div><strong>سجل العمليات</strong><p>{selectedCurrency ? `المجاميع أعلاه تخص ${selectedCurrency} فقط.` : 'اختر عملة من الفلاتر لإظهار المجاميع دون خلط العملات.'}</p></div><span className="count-pill">{filtered.length} عملية</span></div>
      <div className="data-list transaction-list">
        {filtered.length === 0 ? <div className="empty-state"><strong>لا توجد عمليات مطابقة للفلاتر.</strong><p>غيّر البحث أو امسح أحد الفلاتر لعرض نتائج أكثر.</p></div> : filtered.map((row) => <button className="data-row transaction-row" onClick={() => onOpen(row.id)} key={String(row.id)}>
          <div className="transaction-primary">
            <div className="transaction-title"><b>{String(row.transaction_no)}</b><span className="type-pill">{transactionTypeLabel(row.transaction_type)}</span></div>
            <small>{String(row.customer_name ?? 'بدون طرف')} · {formatDate(row.transaction_datetime)}</small>
          </div>
          <div className="row-meta transaction-finance">
            <b>{formatNumber(row.total_amount)} <span>{String(row.currency)}</span></b>
            <small>{paymentLabel(row.payment_status)} · ربح {formatNumber(row.estimated_profit)}</small>
          </div>
        </button>)}
      </div>
    </div>
  </div>;
}
