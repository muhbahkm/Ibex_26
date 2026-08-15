'use client';

import { FormEvent, useMemo, useState } from 'react';

type Currency = 'YER' | 'SAR' | 'USD';
type BalanceRow = { currency?: unknown; balance?: unknown };
type StatementRow = Record<string, unknown>;

type Props = {
  customerId: string;
  balances: BalanceRow[];
  onReceiptCreated: () => Promise<void> | void;
};

function formatNumber(value: unknown) {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(Number(value ?? 0));
}

function formatDate(value: unknown) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('ar-YE', { dateStyle: 'medium' }).format(new Date(String(value)));
}

function messageFor(code: string) {
  if (code === 'RECEIPT_EXCEEDS_CUSTOMER_BALANCE') return 'المبلغ أكبر من الرصيد المستحق على العميل.';
  if (code === 'CUSTOMER_HAS_NO_OUTSTANDING_BALANCE') return 'لا يوجد رصيد مستحق يمكن تحصيله.';
  if (code === 'CASH_ACCOUNT_NOT_FOUND') return 'لا يوجد صندوق نشط لهذه العملة.';
  return 'تعذر إكمال الإجراء. حاول مرة أخرى.';
}

export function CustomerActionPanel({ customerId, balances, onReceiptCreated }: Props) {
  const positiveBalances = useMemo(() => balances
    .map((row) => ({ currency: String(row.currency) as Currency, balance: Number(row.balance ?? 0) }))
    .filter((row) => ['YER', 'SAR', 'USD'].includes(row.currency) && row.balance > 0), [balances]);

  const [mode, setMode] = useState<'none' | 'receipt' | 'statement'>('none');
  const [currency, setCurrency] = useState<Currency>(positiveBalances[0]?.currency ?? 'YER');
  const [amount, setAmount] = useState('');
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [statement, setStatement] = useState<StatementRow[]>([]);

  async function createReceipt(event: FormEvent) {
    event.preventDefault();
    setNotice(null);
    const numericAmount = Number(amount);
    if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      setNotice('أدخل مبلغًا صحيحًا أكبر من صفر.');
      return;
    }

    setBusy(true);
    try {
      const response = await fetch('/api/receipts', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ customer_id: customerId, currency, amount: numericAmount, notes: notes.trim() || undefined }),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? 'RECEIPT_CREATE_FAILED');
      setNotice(`تم إنشاء سند القبض ${body.transaction.transaction_no} بنجاح.`);
      setAmount('');
      setNotes('');
      await onReceiptCreated();
    } catch (error) {
      setNotice(messageFor(error instanceof Error ? error.message : 'RECEIPT_CREATE_FAILED'));
    } finally {
      setBusy(false);
    }
  }

  async function loadStatement(event?: FormEvent) {
    event?.preventDefault();
    setBusy(true);
    setNotice(null);
    try {
      const params = new URLSearchParams({ customerId });
      if (currency) params.set('currency', currency);
      if (dateFrom) params.set('dateFrom', dateFrom);
      if (dateTo) params.set('dateTo', dateTo);
      const response = await fetch(`/api/customers/statement?${params.toString()}`);
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? 'STATEMENT_READ_FAILED');
      setStatement(Array.isArray(body.rows) ? body.rows : []);
    } catch {
      setNotice('تعذر تحميل كشف الحساب.');
    } finally {
      setBusy(false);
    }
  }

  return <section className="customer-actions surface">
    <div className="surface-head action-head">
      <div><strong>إجراءات العميل</strong><p>التحصيل وكشف الحساب من نفس الملف، دون مغادرة السياق.</p></div>
      <div className="action-tabs">
        <button className={mode === 'receipt' ? 'active' : ''} onClick={() => { setMode(mode === 'receipt' ? 'none' : 'receipt'); setNotice(null); }}>سند قبض</button>
        <button className={mode === 'statement' ? 'active' : ''} onClick={() => { setMode(mode === 'statement' ? 'none' : 'statement'); setNotice(null); }}>كشف حساب</button>
      </div>
    </div>

    {notice && <div className="inline-notice">{notice}</div>}

    {mode === 'receipt' && <form className="action-form" onSubmit={createReceipt}>
      <label><span>العملة</span><select value={currency} onChange={(event) => setCurrency(event.target.value as Currency)}>{positiveBalances.map((row) => <option key={row.currency} value={row.currency}>{row.currency} — مستحق {formatNumber(row.balance)}</option>)}</select></label>
      <label><span>المبلغ</span><input inputMode="decimal" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0" /></label>
      <label className="wide"><span>ملاحظة</span><input value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="اختياري" /></label>
      <div className="action-submit"><button disabled={busy || positiveBalances.length === 0} type="submit">{busy ? 'جارٍ التسجيل…' : 'تسجيل سند القبض'}</button></div>
      {positiveBalances.length === 0 && <small className="form-hint">لا توجد أرصدة موجبة قابلة للتحصيل.</small>}
    </form>}

    {mode === 'statement' && <div className="statement-panel">
      <form className="statement-filters" onSubmit={loadStatement}>
        <label><span>العملة</span><select value={currency} onChange={(event) => setCurrency(event.target.value as Currency)}><option value="YER">YER</option><option value="SAR">SAR</option><option value="USD">USD</option></select></label>
        <label><span>من</span><input type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} /></label>
        <label><span>إلى</span><input type="date" value={dateTo} onChange={(event) => setDateTo(event.target.value)} /></label>
        <button disabled={busy} type="submit">{busy ? 'جارٍ التحميل…' : 'عرض الكشف'}</button>
      </form>
      <div className="statement-list">
        {statement.length === 0 ? <div className="statement-empty">اختر الفترة ثم اضغط «عرض الكشف».</div> : statement.map((row, index) => <div className="statement-row" key={`${row.entry_datetime}-${index}`}>
          <div><b>{String(row.description ?? row.transaction_no ?? 'حركة حساب')}</b><small>{formatDate(row.entry_datetime)} · {String(row.transaction_no ?? '')}</small></div>
          <div className="statement-values"><span>مدين {formatNumber(row.debit_amount)}</span><span>دائن {formatNumber(row.credit_amount)}</span><b>الرصيد {formatNumber(row.balance_after)} {String(row.currency ?? currency)}</b></div>
        </div>)}
      </div>
    </div>}
  </section>;
}
