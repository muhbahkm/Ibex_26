'use client';

import { FormEvent, useRef, useState } from 'react';

type Row = Record<string, unknown>;
type Props = {
  value: Row;
  onBack: () => void;
  onOpenCustomer: (customerId: unknown) => void;
  onCancelled?: (transactionId: string) => Promise<void> | void;
};

function asRows(value: unknown) { return Array.isArray(value) ? value as Row[] : []; }
function asRecord(value: unknown) { return value && typeof value === 'object' ? value as Row : {}; }
function formatNumber(value: unknown) { return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(Number(value ?? 0)); }
function formatDate(value: unknown) { if (!value) return '—'; return new Intl.DateTimeFormat('ar-YE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(String(value))); }
function escapeHtml(value: unknown) { return String(value ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;'); }

export function TransactionDetailPanel({ value, onBack, onOpenCustomer, onCancelled }: Props) {
  const tx = asRecord(value.transaction);
  const items = asRows(value.items);
  const currency = String(tx.currency ?? '');
  const cancelLock = useRef(false);
  const [cancelMode, setCancelMode] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  const [cancelReview, setCancelReview] = useState(false);
  const [cancelBusy, setCancelBusy] = useState(false);
  const [cancelNotice, setCancelNotice] = useState<string | null>(null);
  const isCancelled = String(tx.transaction_status ?? '') === 'cancelled';

  function printTransaction() {
    const popup = window.open('', '_blank');
    if (!popup) return;
    popup.opener = null;
    const itemRows = items.map((row) => `<tr><td>${escapeHtml(row.product_name)}</td><td>${escapeHtml(`${formatNumber(row.quantity)} ${String(row.unit_name ?? '')}`)}</td><td>${escapeHtml(formatNumber(row.unit_price))}</td><td>${escapeHtml(formatNumber(row.line_total))}</td></tr>`).join('');
    popup.document.write(`<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>${escapeHtml(tx.transaction_no)}</title><style>body{font-family:Arial,"Noto Sans Arabic",sans-serif;margin:30px;color:#17191b}h1{font-size:22px;margin-bottom:6px}.muted{color:#666}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:20px 0}.card{border:1px solid #ddd;border-radius:10px;padding:10px}.card span{display:block;color:#777;font-size:11px}.card b{font-size:17px}table{width:100%;border-collapse:collapse;font-size:12px}th,td{padding:9px 7px;border-bottom:1px solid #ddd;text-align:right}th{background:#f5f5f3}@media print{body{margin:12mm}}</style></head><body><h1>${escapeHtml(tx.transaction_type_label ?? 'عملية')}</h1><div class="muted">${escapeHtml(tx.transaction_no)} · ${escapeHtml(formatDate(tx.transaction_datetime))} · ${escapeHtml(tx.customer_name ?? 'بدون طرف')}</div><div class="cards"><div class="card"><span>الإجمالي</span><b>${escapeHtml(formatNumber(tx.total_amount))} ${escapeHtml(currency)}</b></div><div class="card"><span>المدفوع</span><b>${escapeHtml(formatNumber(tx.paid_amount))}</b></div><div class="card"><span>المتبقي</span><b>${escapeHtml(formatNumber(tx.remaining_amount))}</b></div><div class="card"><span>الربح التقديري</span><b>${escapeHtml(formatNumber(tx.estimated_profit))}</b></div></div><table><thead><tr><th>الصنف</th><th>الكمية</th><th>سعر الوحدة</th><th>الإجمالي</th></tr></thead><tbody>${itemRows}</tbody></table><script>window.onload=()=>window.print();<\/script></body></html>`);
    popup.document.close();
  }

  function reviewCancellation(event: FormEvent) {
    event.preventDefault();
    const reason = cancelReason.trim();
    setCancelNotice(null);
    if (reason.length < 4) {
      setCancelNotice('اكتب سببًا واضحًا للإلغاء قبل المتابعة.');
      return;
    }
    setCancelReview(true);
  }

  async function confirmCancellation() {
    const transactionId = String(tx.id ?? '');
    if (!transactionId || cancelLock.current) return;
    cancelLock.current = true;
    setCancelBusy(true);
    setCancelNotice(null);
    try {
      const response = await fetch('/api/transactions/cancel', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ transaction_id: transactionId, reason: cancelReason.trim() }),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? 'TRANSACTION_CANCEL_FAILED');
      setCancelMode(false);
      setCancelReview(false);
      setCancelNotice('تم إلغاء العملية وعكس آثارها المالية عبر المحرك المركزي.');
      await onCancelled?.(transactionId);
    } catch (error) {
      const code = error instanceof Error ? error.message : 'TRANSACTION_CANCEL_FAILED';
      setCancelNotice(code === 'TRANSACTION_ALREADY_CANCELLED' ? 'العملية ملغاة بالفعل.' : 'تعذر إلغاء العملية. راجع الحالة ثم حاول مرة أخرى.');
    } finally {
      cancelLock.current = false;
      setCancelBusy(false);
    }
  }

  return <div className="detail-stack">
    <div className="detail-hero">
      <button className="back-button" onClick={onBack}>رجوع</button>
      <div><span className="eyebrow">تفاصيل العملية</span><h2>{String(tx.transaction_no ?? 'عملية')}</h2><p>{String(tx.transaction_type_label ?? tx.transaction_type ?? '')} · {formatDate(tx.transaction_datetime)} · {String(tx.customer_name ?? 'بدون طرف')}</p></div>
      <div className="hero-stat"><small>الإجمالي</small><b>{formatNumber(tx.total_amount)} {currency}</b></div>
    </div>

    <div className="action-tabs">
      <button type="button" onClick={printTransaction}>طباعة العملية</button>
      {Boolean(tx.customer_id) && <button type="button" onClick={() => onOpenCustomer(tx.customer_id)}>فتح العميل</button>}
      {!isCancelled && <button className="danger-action" type="button" onClick={() => { setCancelMode(!cancelMode); setCancelReview(false); setCancelNotice(null); }}>إلغاء العملية</button>}
    </div>

    {cancelNotice && <div className="inline-notice">{cancelNotice}</div>}
    {isCancelled && <div className="inline-notice danger-notice"><strong>هذه العملية ملغاة.</strong>{tx.cancel_reason ? <span> السبب: {String(tx.cancel_reason)}</span> : null}</div>}
    {cancelMode && !isCancelled && <div className="surface cancel-surface">
      <div className="surface-head"><div><strong>إلغاء العملية</strong><p>الإلغاء لا يحذف السجل؛ سيعكس أثر الصندوق ودفتر العميل عبر الدالة المالية المركزية.</p></div></div>
      {!cancelReview ? <form className="cancel-form" onSubmit={reviewCancellation}><label><span>سبب الإلغاء</span><textarea value={cancelReason} onChange={(event) => setCancelReason(event.target.value)} rows={3} maxLength={300} placeholder="مثال: أُدخلت الفاتورة بالخطأ" /></label><div className="draft-actions"><button className="secondary" type="button" onClick={() => setCancelMode(false)}>تراجع</button><button className="danger-action" type="submit">مراجعة الإلغاء</button></div></form> : <div className="cancel-review"><strong>تأكيد أخير</strong><p>سيتم إلغاء العملية <b>{String(tx.transaction_no ?? '')}</b> بقيمة <b>{formatNumber(tx.total_amount)} {currency}</b> وعكس آثارها المالية. السبب: «{cancelReason.trim()}».</p><div className="draft-actions"><button className="secondary" type="button" onClick={() => setCancelReview(false)} disabled={cancelBusy}>تعديل السبب</button><button className="danger-action" type="button" onClick={confirmCancellation} disabled={cancelBusy}>{cancelBusy ? 'جارٍ الإلغاء…' : 'تأكيد الإلغاء والعكس'}</button></div></div>}
    </div>}

    <div className="balance-grid">
      <div className="balance-card"><span>المدفوع</span><b>{formatNumber(tx.paid_amount)}</b><small>{String(tx.payment_status_label ?? tx.payment_status ?? '')}</small></div>
      <div className="balance-card"><span>المتبقي</span><b>{formatNumber(tx.remaining_amount)}</b><small>{currency}</small></div>
      <div className="balance-card"><span>الربح التقديري</span><b>{formatNumber(tx.estimated_profit)}</b><small>{currency}</small></div>
      <div className="balance-card"><span>الحالة</span><b>{String(tx.transaction_status ?? '—')}</b><small>{String(tx.cash_account_name ?? 'بدون صندوق')}</small></div>
    </div>

    <div className="surface"><div className="surface-head"><div><strong>معلومات التسجيل</strong><p>بيانات تشغيلية تساعد على المراجعة والتتبع.</p></div></div><div className="metric-pairs"><div><span>أنشأها</span><b>{String(tx.created_by_name ?? '—')}</b></div><div><span>الصندوق</span><b>{String(tx.cash_account_name ?? '—')}</b></div><div><span>حالة السداد</span><b>{String(tx.payment_status_label ?? tx.payment_status ?? '—')}</b></div><div><span>الملاحظات</span><b>{String(tx.notes ?? 'لا توجد ملاحظات')}</b></div></div></div>

    <div className="surface"><div className="surface-head"><div><strong>بنود العملية</strong><p>الكمية والسعر والتكلفة والربح لكل بند.</p></div><span className="count-pill">{items.length} بند</span></div><div className="data-list">{items.length === 0 ? <div className="empty-state"><strong>لا توجد بنود لهذه الحركة.</strong></div> : items.map((row) => <div className="data-row static" key={String(row.id)}><div><b>{String(row.product_name ?? '')}</b><small>{formatNumber(row.quantity)} {String(row.unit_name ?? '')} × {formatNumber(row.unit_price)} {String(row.currency ?? currency)}</small></div><div className="row-meta"><b>{formatNumber(row.line_total)} {String(row.currency ?? currency)}</b><small>تكلفة {formatNumber(row.estimated_line_cost)} · ربح {formatNumber(row.estimated_line_profit)}</small></div></div>)}</div></div>
  </div>;
}
