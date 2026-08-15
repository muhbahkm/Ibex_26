'use client';

import { FormEvent, useMemo, useRef, useState } from 'react';

type Currency = 'YER' | 'SAR' | 'USD';
type BalanceRow = { currency?: unknown; balance?: unknown };
type StatementRow = Record<string, unknown>;
type PendingReceipt = { currency: Currency; amount: number; notes?: string };

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

function escapeHtml(value: unknown) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
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

  const receiptSubmitLock = useRef(false);
  const [mode, setMode] = useState<'none' | 'receipt' | 'statement'>('none');
  const [currency, setCurrency] = useState<Currency>(positiveBalances[0]?.currency ?? 'YER');
  const [amount, setAmount] = useState('');
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [pendingReceipt, setPendingReceipt] = useState<PendingReceipt | null>(null);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [statement, setStatement] = useState<StatementRow[]>([]);

  const selectedBalance = positiveBalances.find((row) => row.currency === currency)?.balance ?? 0;
  const statementSummary = useMemo(() => statement.reduce<{ debit: number; credit: number; ending: number }>((summary, row) => ({
    debit: summary.debit + Number(row.debit_amount ?? 0),
    credit: summary.credit + Number(row.credit_amount ?? 0),
    ending: Number(row.balance_after ?? summary.ending),
  }), { debit: 0, credit: 0, ending: 0 }), [statement]);

  function reviewReceipt(event: FormEvent) {
    event.preventDefault();
    setNotice(null);
    const numericAmount = Number(amount);
    if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      setNotice('أدخل مبلغًا صحيحًا أكبر من صفر.');
      return;
    }
    if (selectedBalance <= 0) {
      setNotice('لا يوجد رصيد مستحق بهذه العملة.');
      return;
    }
    if (numericAmount > selectedBalance) {
      setNotice('المبلغ أكبر من الرصيد المستحق على العميل.');
      return;
    }
    setPendingReceipt({ currency, amount: numericAmount, notes: notes.trim() || undefined });
  }

  async function confirmReceipt() {
    if (!pendingReceipt || receiptSubmitLock.current) return;
    receiptSubmitLock.current = true;
    setBusy(true);
    setNotice(null);
    try {
      const response = await fetch('/api/receipts', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ customer_id: customerId, ...pendingReceipt }),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? 'RECEIPT_CREATE_FAILED');
      setNotice(`تم إنشاء سند القبض ${body.transaction.transaction_no} بنجاح.`);
      setAmount('');
      setNotes('');
      setPendingReceipt(null);
      await onReceiptCreated();
    } catch (error) {
      setNotice(messageFor(error instanceof Error ? error.message : 'RECEIPT_CREATE_FAILED'));
    } finally {
      receiptSubmitLock.current = false;
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

  function printStatement() {
    if (statement.length === 0) {
      setNotice('اعرض كشف الحساب أولًا قبل الطباعة.');
      return;
    }

    const rows = statement.map((row) => `
      <tr>
        <td>${escapeHtml(formatDate(row.entry_datetime))}</td>
        <td>${escapeHtml(row.transaction_no || '—')}</td>
        <td>${escapeHtml(row.description || 'حركة حساب')}</td>
        <td>${escapeHtml(formatNumber(row.debit_amount))}</td>
        <td>${escapeHtml(formatNumber(row.credit_amount))}</td>
        <td>${escapeHtml(formatNumber(row.balance_after))}</td>
      </tr>`).join('');

    const popup = window.open('', '_blank');
    if (!popup) {
      setNotice('تعذر فتح نافذة الطباعة. اسمح بالنوافذ المنبثقة لهذا الموقع ثم حاول مجددًا.');
      return;
    }
    popup.opener = null;
    popup.document.write(`<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>كشف حساب</title><style>
      body{font-family:Arial,"Noto Sans Arabic",sans-serif;margin:32px;color:#17191b}h1{font-size:22px;margin:0 0 8px}.meta{color:#666;margin-bottom:24px}.summary{display:flex;gap:12px;margin:18px 0}.card{border:1px solid #ddd;border-radius:10px;padding:10px 14px;min-width:130px}.card span{display:block;color:#777;font-size:12px}.card b{font-size:18px}table{width:100%;border-collapse:collapse;font-size:12px}th,td{border-bottom:1px solid #ddd;padding:9px 7px;text-align:right}th{background:#f5f5f3}@media print{body{margin:12mm}.no-print{display:none}}
    </style></head><body><h1>كشف حساب العميل</h1><div class="meta">${escapeHtml(currency)}${dateFrom ? ` · من ${escapeHtml(dateFrom)}` : ''}${dateTo ? ` · إلى ${escapeHtml(dateTo)}` : ''}</div><div class="summary"><div class="card"><span>إجمالي المدين</span><b>${escapeHtml(formatNumber(statementSummary.debit))}</b></div><div class="card"><span>إجمالي الدائن</span><b>${escapeHtml(formatNumber(statementSummary.credit))}</b></div><div class="card"><span>الرصيد الختامي</span><b>${escapeHtml(formatNumber(statementSummary.ending))} ${escapeHtml(currency)}</b></div></div><table><thead><tr><th>التاريخ</th><th>رقم العملية</th><th>البيان</th><th>مدين</th><th>دائن</th><th>الرصيد</th></tr></thead><tbody>${rows}</tbody></table><script>window.onload=()=>window.print();<\/script></body></html>`);
    popup.document.close();
  }

  return <section className="customer-actions surface">
    <div className="surface-head action-head">
      <div><strong>إجراءات العميل</strong><p>التحصيل وكشف الحساب من نفس الملف، دون مغادرة السياق.</p></div>
      <div className="action-tabs">
        <button className={mode === 'receipt' ? 'active' : ''} onClick={() => { setMode(mode === 'receipt' ? 'none' : 'receipt'); setNotice(null); setPendingReceipt(null); }}>سند قبض</button>
        <button className={mode === 'statement' ? 'active' : ''} onClick={() => { setMode(mode === 'statement' ? 'none' : 'statement'); setNotice(null); setPendingReceipt(null); }}>كشف حساب</button>
      </div>
    </div>

    {notice && <div className="inline-notice">{notice}</div>}

    {mode === 'receipt' && <>
      <form className="action-form" onSubmit={reviewReceipt}>
        <label><span>العملة</span><select value={currency} onChange={(event) => { setCurrency(event.target.value as Currency); setPendingReceipt(null); }}>{positiveBalances.map((row) => <option key={row.currency} value={row.currency}>{row.currency} — مستحق {formatNumber(row.balance)}</option>)}</select></label>
        <label><span>المبلغ</span><input inputMode="decimal" value={amount} onChange={(event) => { setAmount(event.target.value); setPendingReceipt(null); }} placeholder="0" /></label>
        <label className="wide"><span>ملاحظة</span><input value={notes} onChange={(event) => { setNotes(event.target.value); setPendingReceipt(null); }} placeholder="اختياري" /></label>
        <div className="action-submit"><button disabled={busy || positiveBalances.length === 0} type="submit">مراجعة سند القبض</button></div>
        {positiveBalances.length === 0 && <small className="form-hint">لا توجد أرصدة موجبة قابلة للتحصيل.</small>}
      </form>
      {pendingReceipt && <div className="inline-notice draft-card">
        <div><strong>راجع قبل الاعتماد</strong><p>سيتم تسجيل سند قبض بقيمة <b>{formatNumber(pendingReceipt.amount)} {pendingReceipt.currency}</b>. الرصيد قبل التحصيل {formatNumber(selectedBalance)}، والمتبقي المتوقع {formatNumber(selectedBalance - pendingReceipt.amount)}.</p></div>
        <div className="draft-actions"><button className="secondary" type="button" onClick={() => setPendingReceipt(null)} disabled={busy}>تعديل</button><button type="button" onClick={confirmReceipt} disabled={busy}>{busy ? 'جارٍ الاعتماد…' : 'اعتماد سند القبض'}</button></div>
      </div>}
    </>}

    {mode === 'statement' && <div className="statement-panel">
      <form className="statement-filters" onSubmit={loadStatement}>
        <label><span>العملة</span><select value={currency} onChange={(event) => setCurrency(event.target.value as Currency)}><option value="YER">YER</option><option value="SAR">SAR</option><option value="USD">USD</option></select></label>
        <label><span>من</span><input type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} /></label>
        <label><span>إلى</span><input type="date" value={dateTo} onChange={(event) => setDateTo(event.target.value)} /></label>
        <button disabled={busy} type="submit">{busy ? 'جارٍ التحميل…' : 'عرض الكشف'}</button>
        <button disabled={busy || statement.length === 0} type="button" onClick={printStatement}>طباعة</button>
      </form>
      {statement.length > 0 && <div className="balance-grid"><div className="balance-card"><span>إجمالي المدين</span><b>{formatNumber(statementSummary.debit)}</b><small>{currency}</small></div><div className="balance-card"><span>إجمالي الدائن</span><b>{formatNumber(statementSummary.credit)}</b><small>{currency}</small></div><div className="balance-card"><span>الرصيد الختامي</span><b>{formatNumber(statementSummary.ending)}</b><small>{currency}</small></div></div>}
      <div className="statement-list">
        {statement.length === 0 ? <div className="statement-empty">اختر الفترة ثم اضغط «عرض الكشف».</div> : statement.map((row, index) => <div className="statement-row" key={`${row.entry_datetime}-${index}`}>
          <div><b>{String(row.description ?? row.transaction_no ?? 'حركة حساب')}</b><small>{formatDate(row.entry_datetime)} · {String(row.transaction_no ?? '')}</small></div>
          <div className="statement-values"><span>مدين {formatNumber(row.debit_amount)}</span><span>دائن {formatNumber(row.credit_amount)}</span><b>الرصيد {formatNumber(row.balance_after)} {String(row.currency ?? currency)}</b></div>
        </div>)}
      </div>
    </div>}
  </section>;
}
