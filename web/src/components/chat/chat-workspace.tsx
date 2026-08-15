'use client';

import { FormEvent, useEffect, useMemo, useState } from 'react';

type Props = { displayName: string; roleLabel: string; accountLinked: boolean; businessLabel: string };
type DraftReady = { status: 'draft_ready'; source_message: string; draft: Record<string, unknown>; preview: { customer_name: string; product_name: string; unit_name: string; quantity: number; unit_price: number; currency: string; total_amount: number; paid_amount: number; remaining_amount: number } };
type Clarification = { status: 'needs_clarification'; question: string; candidates: { id: string; label: string }[] };
type ChatState = { kind: 'idle' } | { kind: 'loading'; message: string } | { kind: 'draft'; value: DraftReady } | { kind: 'clarification'; value: Clarification } | { kind: 'success'; transactionNo: string } | { kind: 'error'; message: string };
type Section = 'chat' | 'customers' | 'transactions' | 'debts' | 'reports';
type WorkspaceData = { section: string; rows?: Record<string, unknown>[]; topProducts?: Record<string, unknown>[] };
type DetailState = { kind: 'customer' | 'transaction'; value: Record<string, unknown> } | null;

const tabs: { id: Section; label: string }[] = [
  { id: 'chat', label: 'محادثة جديدة' }, { id: 'customers', label: 'العملاء' }, { id: 'transactions', label: 'العمليات' }, { id: 'debts', label: 'الديون' }, { id: 'reports', label: 'التقارير' },
];

function formatNumber(value: unknown) { return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(Number(value ?? 0)); }
function formatDate(value: unknown) { if (!value) return '—'; return new Intl.DateTimeFormat('ar-YE', { dateStyle: 'medium' }).format(new Date(String(value))); }
function sectionTitle(section: Section) { if (section === 'customers') return 'العملاء والحسابات'; if (section === 'transactions') return 'سجل العمليات'; if (section === 'debts') return 'متابعة الديون'; if (section === 'reports') return 'التقارير والمؤشرات'; return 'كيف أساعدك في إدارة العمل؟'; }
function asRows(value: unknown) { return Array.isArray(value) ? value as Record<string, unknown>[] : []; }
function asRecord(value: unknown) { return value && typeof value === 'object' ? value as Record<string, unknown> : {}; }

export function ChatWorkspace({ displayName, roleLabel, accountLinked, businessLabel }: Props) {
  const [state, setState] = useState<ChatState>({ kind: 'idle' });
  const [message, setMessage] = useState('');
  const [section, setSection] = useState<Section>('chat');
  const [workspace, setWorkspace] = useState<WorkspaceData | null>(null);
  const [workspaceLoading, setWorkspaceLoading] = useState(false);
  const [workspaceError, setWorkspaceError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [detail, setDetail] = useState<DetailState>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  useEffect(() => {
    if (section === 'chat' || !accountLinked) return;
    let cancelled = false;
    setWorkspaceLoading(true); setWorkspaceError(null); setDetail(null);
    fetch(`/api/workspace?section=${section}`)
      .then(async (response) => { const body = await response.json(); if (!response.ok) throw new Error(body.error ?? 'تعذر تحميل البيانات.'); return body as WorkspaceData; })
      .then((body) => { if (!cancelled) setWorkspace(body); })
      .catch((error) => { if (!cancelled) setWorkspaceError(error instanceof Error ? error.message : 'تعذر تحميل البيانات.'); })
      .finally(() => { if (!cancelled) setWorkspaceLoading(false); });
    return () => { cancelled = true; };
  }, [section, accountLinked]);

  const filteredRows = useMemo(() => {
    const rows = workspace?.rows ?? []; const normalized = query.trim().toLocaleLowerCase('ar');
    if (!normalized) return rows;
    return rows.filter((row) => Object.values(row).some((value) => String(value ?? '').toLocaleLowerCase('ar').includes(normalized)));
  }, [workspace, query]);

  async function openDetail(kind: 'customer' | 'transaction', id: unknown) {
    if (!id) return; setDetailLoading(true); setWorkspaceError(null);
    try {
      const response = await fetch(`/api/workspace?detail=${kind}&id=${encodeURIComponent(String(id))}`);
      const body = await response.json(); if (!response.ok) throw new Error(body.error ?? 'تعذر تحميل التفاصيل.');
      setDetail({ kind, value: asRecord(body.value) });
    } catch (error) { setWorkspaceError(error instanceof Error ? error.message : 'تعذر تحميل التفاصيل.'); }
    finally { setDetailLoading(false); }
  }

  async function submit(event: FormEvent) {
    event.preventDefault(); const value = message.trim(); if (!value || !accountLinked) return; setState({ kind: 'loading', message: value });
    const response = await fetch('/api/agent/interpret', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ message: value }) });
    const body = await response.json(); if (!response.ok) { setState({ kind: 'error', message: body.error ?? 'تعذر فهم العملية.' }); return; }
    if (body.status === 'needs_clarification') { setState({ kind: 'clarification', value: body }); return; } setState({ kind: 'draft', value: body });
  }

  async function confirm() {
    if (state.kind !== 'draft') return;
    const response = await fetch('/api/sales/confirm', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(state.value.draft) });
    const body = await response.json(); if (!response.ok) { setState({ kind: 'error', message: body.error ?? 'تعذر اعتماد العملية.' }); return; }
    setState({ kind: 'success', transactionNo: body.transaction.transaction_no }); setMessage('');
  }

  function renderCustomerDetail(value: Record<string, unknown>) {
    const customer = asRecord(value.customer); const balances = asRows(value.balances); const ledger = asRows(value.ledger);
    return <div className="detail-stack"><div className="detail-hero"><button className="back-button" onClick={() => setDetail(null)}>رجوع</button><div><span className="eyebrow">ملف العميل</span><h2>{String(customer.display_name ?? 'عميل')}</h2><p>{customer.phone ? String(customer.phone) : 'بدون رقم هاتف'} · آخر حركة {formatDate(customer.last_transaction_at)}</p></div><div className="hero-stat"><small>إجمالي المبيعات</small><b>{formatNumber(customer.total_sales_amount)}</b></div></div><div className="balance-grid">{balances.length ? balances.map((row) => <div className="balance-card" key={String(row.currency)}><span>{String(row.currency)}</span><b>{formatNumber(row.balance)}</b><small>الرصيد الحالي</small></div>) : <div className="balance-card"><span>الحساب</span><b>0</b><small>لا توجد أرصدة معلقة</small></div>}</div><div className="surface"><div className="surface-head"><div><strong>حركة الحساب</strong><p>أحدث قيود دفتر العميل.</p></div><span className="count-pill">{ledger.length} قيد</span></div><div className="data-list">{ledger.map((row, index) => <div className="data-row static" key={`${row.entry_datetime}-${index}`}><div><b>{String(row.description ?? row.transaction_no ?? 'حركة حساب')}</b><small>{formatDate(row.entry_datetime)} · {String(row.currency ?? '')}</small></div><div className="row-meta"><b>{Number(row.debit_amount ?? 0) > 0 ? `+${formatNumber(row.debit_amount)}` : `-${formatNumber(row.credit_amount)}`}</b><small>الرصيد {formatNumber(row.balance_after)}</small></div></div>)}</div></div></div>;
  }

  function renderTransactionDetail(value: Record<string, unknown>) {
    const tx = asRecord(value.transaction); const items = asRows(value.items);
    return <div className="detail-stack"><div className="detail-hero"><button className="back-button" onClick={() => setDetail(null)}>رجوع</button><div><span className="eyebrow">تفاصيل العملية</span><h2>{String(tx.transaction_no ?? 'عملية')}</h2><p>{String(tx.transaction_type_label ?? tx.transaction_type ?? '')} · {formatDate(tx.transaction_datetime)} · {String(tx.customer_name ?? 'بدون طرف')}</p></div><div className="hero-stat"><small>الإجمالي</small><b>{formatNumber(tx.total_amount)} {String(tx.currency ?? '')}</b></div></div><div className="balance-grid"><div className="balance-card"><span>المدفوع</span><b>{formatNumber(tx.paid_amount)}</b><small>{String(tx.payment_status_label ?? tx.payment_status ?? '')}</small></div><div className="balance-card"><span>المتبقي</span><b>{formatNumber(tx.remaining_amount)}</b><small>{String(tx.currency ?? '')}</small></div><div className="balance-card"><span>الربح التقديري</span><b>{formatNumber(tx.estimated_profit)}</b><small>{String(tx.currency ?? '')}</small></div></div><div className="surface"><div className="surface-head"><div><strong>بنود العملية</strong><p>الكمية والسعر والتكلفة والربح لكل بند.</p></div><span className="count-pill">{items.length} بند</span></div><div className="data-list">{items.map((row) => <div className="data-row static" key={String(row.id)}><div><b>{String(row.product_name ?? '')}</b><small>{formatNumber(row.quantity)} {String(row.unit_name ?? '')} × {formatNumber(row.unit_price)} {String(row.currency ?? tx.currency ?? '')}</small></div><div className="row-meta"><b>{formatNumber(row.line_total)} {String(row.currency ?? tx.currency ?? '')}</b><small>ربح {formatNumber(row.estimated_line_profit)}</small></div></div>)}</div></div></div>;
  }

  function renderOperationalSection() {
    if (detailLoading) return <div className="surface empty-state"><strong>جارٍ تحميل التفاصيل…</strong></div>;
    if (detail?.kind === 'customer') return renderCustomerDetail(detail.value);
    if (detail?.kind === 'transaction') return renderTransactionDetail(detail.value);
    if (workspaceLoading) return <div className="surface empty-state"><strong>جارٍ تحميل البيانات…</strong></div>;
    if (workspaceError) return <div className="surface empty-state"><strong>تعذر تحميل البيانات</strong><p>{workspaceError}</p></div>;

    if (section === 'customers') return <div className="surface"><div className="surface-head"><div><strong>حسابات العملاء</strong><p>الأرصدة مفصولة حسب العملة، مع آخر حركة ظاهرة.</p></div><span className="count-pill">{filteredRows.length} حساب</span></div><div className="data-list">{filteredRows.map((row) => <button className="data-row" onClick={() => openDetail('customer', row.customer_id)} key={`${row.customer_id}-${row.currency}`}><div><b>{String(row.display_name ?? 'بدون اسم')}</b><small>{row.phone ? String(row.phone) : 'لا يوجد رقم هاتف'}</small></div><div className="row-meta"><b>{formatNumber(row.balance)} {String(row.currency)}</b><small>آخر حركة {formatDate(row.last_transaction_at)}</small></div></button>)}</div></div>;
    if (section === 'transactions') return <div className="surface"><div className="surface-head"><div><strong>آخر العمليات</strong><p>عرض مباشر للحركات مع حالة السداد والربحية.</p></div><span className="count-pill">{filteredRows.length} عملية</span></div><div className="data-list">{filteredRows.map((row) => <button className="data-row" onClick={() => openDetail('transaction', row.id)} key={String(row.id)}><div><b>{String(row.transaction_no)}</b><small>{String(row.customer_name ?? 'بدون طرف')} · {formatDate(row.transaction_datetime)}</small></div><div className="row-meta"><b>{formatNumber(row.total_amount)} {String(row.currency)}</b><small>{String(row.payment_status)} · ربح {formatNumber(row.estimated_profit)}</small></div></button>)}</div></div>;
    if (section === 'debts') return <div className="surface"><div className="surface-head"><div><strong>الديون المتأخرة</strong><p>الحسابات التي تجاوزت آخر حركة عليها 30 يومًا.</p></div><span className="count-pill danger">{filteredRows.length} متابعة</span></div><div className="data-list">{filteredRows.map((row) => <button className="data-row" onClick={() => openDetail('customer', row.customer_id)} key={`${row.customer_id}-${row.currency}`}><div><b>{String(row.display_name)}</b><small>{row.phone ? String(row.phone) : 'بدون رقم هاتف'} · آخر نشاط {formatDate(row.last_ledger_activity_at)}</small></div><div className="row-meta"><b>{formatNumber(row.balance)} {String(row.currency)}</b><small>{formatNumber(row.days_since_last_activity)} يوم دون حركة</small></div></button>)}</div></div>;
    if (section === 'reports') return <div className="detail-stack"><div className="report-grid">{filteredRows.map((row) => <article className="metric-card" key={String(row.currency)}><div className="metric-title"><strong>{String(row.currency)}</strong><span>آخر 30 يومًا</span></div><div className="metric-main">{formatNumber(row.sales_total)}</div><small>إجمالي المبيعات</small><div className="metric-pairs"><div><span>الربح التقديري</span><b>{formatNumber(row.estimated_profit_total)}</b></div><div><span>المتبقي</span><b>{formatNumber(row.remaining_total)}</b></div><div><span>التحصيل</span><b>{formatNumber(row.collected_total)}</b></div><div><span>عدد المبيعات</span><b>{formatNumber(row.sales_count)}</b></div></div></article>)}</div><div className="surface"><div className="surface-head"><div><strong>الأصناف الأعلى مبيعًا</strong><p>ترتيب آخر 30 يومًا حسب قيمة المبيعات.</p></div></div><div className="data-list">{(workspace?.topProducts ?? []).map((row) => <div className="data-row static" key={`${row.product_name}-${row.currency}`}><div><b>{String(row.product_name)}</b><small>{formatNumber(row.total_quantity)} وحدة · {formatNumber(row.invoices_count)} فاتورة</small></div><div className="row-meta"><b>{formatNumber(row.total_sales)} {String(row.currency)}</b><small>ربح {formatNumber(row.total_estimated_profit)}</small></div></div>)}</div></div></div>;
    return null;
  }

  return <main className="workspace"><aside className="sidebar"><div className="brand"><span className="brand-mark small">B</span><div><strong>باحكم</strong><small>المساعد التشغيلي</small></div></div><nav>{tabs.map((tab) => <button key={tab.id} className={section === tab.id ? 'active' : ''} onClick={() => { setSection(tab.id); setQuery(''); setDetail(null); }}>{tab.label}</button>)}</nav><div className="user-card"><span>{displayName}</span><small>{roleLabel}</small></div></aside><section className="chat"><header><div><h1>{sectionTitle(section)}</h1><p>{accountLinked ? businessLabel : 'تم تسجيل الدخول، لكن يلزم ربط الحساب بمستخدم IBEX قبل تنفيذ العمليات المالية.'}</p></div><span className={accountLinked ? 'status ok' : 'status warn'}>{accountLinked ? 'جاهز' : 'بحاجة إلى ربط'}</span></header>{section === 'chat' ? <><div className="conversation">{state.kind === 'idle' && <div className="welcome-card"><strong>ابدأ بأمر طبيعي</strong><p>مثال: بع كيلو سمرة SI للزبون العام بـ 20000 YER نقدًا.</p><p className="muted">سأحوّل الأمر إلى مسودة، ولن أسجل الحركة قبل موافقتك.</p></div>}{state.kind === 'loading' && <div className="welcome-card"><strong>أحلل العملية…</strong><p>{state.message}</p></div>}{state.kind === 'clarification' && <div className="welcome-card"><strong>أحتاج تحديدًا بسيطًا</strong><p>{state.value.question}</p>{state.value.candidates.map((c) => <div key={c.id} className="candidate">{c.label}</div>)}</div>}{state.kind === 'draft' && <div className="welcome-card draft-card"><strong>مسودة فاتورة مبيعات</strong><div className="draft-grid"><span>العميل</span><b>{state.value.preview.customer_name}</b><span>الصنف</span><b>{state.value.preview.product_name}</b><span>الكمية</span><b>{state.value.preview.quantity} {state.value.preview.unit_name}</b><span>سعر الوحدة</span><b>{state.value.preview.unit_price} {state.value.preview.currency}</b><span>الإجمالي</span><b>{state.value.preview.total_amount} {state.value.preview.currency}</b><span>المدفوع</span><b>{state.value.preview.paid_amount} {state.value.preview.currency}</b><span>المتبقي</span><b>{state.value.preview.remaining_amount} {state.value.preview.currency}</b></div><div className="draft-actions"><button className="secondary" onClick={() => setState({ kind: 'idle' })}>إلغاء</button><button onClick={confirm}>اعتماد العملية</button></div></div>}{state.kind === 'success' && <div className="welcome-card"><strong>تم اعتماد العملية</strong><p>رقم العملية: <b>{state.transactionNo}</b></p><button onClick={() => setState({ kind: 'idle' })}>عملية جديدة</button></div>}{state.kind === 'error' && <div className="welcome-card"><strong>تعذر إكمال الطلب</strong><p>{state.message}</p><button onClick={() => setState({ kind: 'idle' })}>إعادة المحاولة</button></div>}</div><form className="composer" onSubmit={submit}><textarea value={message} onChange={(e) => setMessage(e.target.value)} placeholder="اكتب العملية أو السؤال هنا…" rows={2} disabled={!accountLinked} /><button disabled={!accountLinked || state.kind === 'loading'} type="submit">إرسال</button></form></> : <><div className="operations-toolbar"><div><b>{detail ? 'عرض التفاصيل' : sectionTitle(section)}</b><small>{detail ? 'قراءة تشغيلية من بيانات IBEX الفعلية' : 'واجهة تشغيل مباشرة للبيانات الفعلية في IBEX'}</small></div>{!detail && <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="بحث سريع…" />}</div><div className="operations-content">{renderOperationalSection()}</div></>}</section></main>;
}
