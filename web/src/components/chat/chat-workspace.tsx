'use client';

import { FormEvent, useEffect, useState } from 'react';
import { CustomerActionPanel } from '@/components/customers/customer-action-panel';
import { CustomersPanel } from '@/components/customers/customers-panel';
import { DebtsPanel } from '@/components/debts/debts-panel';
import { MobileNavigation } from '@/components/navigation/mobile-navigation';
import { ReportsPanel } from '@/components/reports/reports-panel';
import { ManualSalePanel } from '@/components/sales/manual-sale-panel';
import { TransactionDetailPanel } from '@/components/transactions/transaction-detail-panel';
import { TransactionsPanel } from '@/components/transactions/transactions-panel';

type Props = { displayName: string; roleLabel: string; accountLinked: boolean; businessId: string; businessLabel: string };
type DraftReady = { status: 'draft_ready'; source_message: string; draft: Record<string, unknown>; preview: { customer_name: string; product_name: string; unit_name: string; quantity: number; unit_price: number; currency: string; total_amount: number; paid_amount: number; remaining_amount: number } };
type Clarification = { status: 'needs_clarification'; question: string; candidates: { id: string; label: string }[] };
type ChatState = { kind: 'idle' } | { kind: 'loading'; message: string } | { kind: 'draft'; value: DraftReady } | { kind: 'clarification'; value: Clarification } | { kind: 'success'; transactionNo: string } | { kind: 'error'; message: string };
type Section = 'chat' | 'customers' | 'transactions' | 'debts' | 'reports';
type WorkspaceData = { section: string; rows?: Record<string, unknown>[]; topProducts?: Record<string, unknown>[] };
type DetailState = { kind: 'customer' | 'transaction'; value: Record<string, unknown> } | null;

const tabs: { id: Section; label: string }[] = [
  { id: 'chat', label: 'محادثة جديدة' },
  { id: 'customers', label: 'العملاء' },
  { id: 'transactions', label: 'العمليات' },
  { id: 'debts', label: 'الديون' },
  { id: 'reports', label: 'التقارير' },
];

function formatNumber(value: unknown) { return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(Number(value ?? 0)); }
function formatDate(value: unknown) { if (!value) return '—'; return new Intl.DateTimeFormat('ar-YE', { dateStyle: 'medium' }).format(new Date(String(value))); }
function sectionTitle(section: Section) { if (section === 'customers') return 'العملاء والحسابات'; if (section === 'transactions') return 'سجل العمليات'; if (section === 'debts') return 'متابعة الديون'; if (section === 'reports') return 'التقارير والمؤشرات'; return 'كيف أساعدك في إدارة العمل؟'; }
function asRows(value: unknown) { return Array.isArray(value) ? value as Record<string, unknown>[] : []; }
function asRecord(value: unknown) { return value && typeof value === 'object' ? value as Record<string, unknown> : {}; }

export function ChatWorkspace({ displayName, roleLabel, accountLinked, businessId, businessLabel }: Props) {
  const [state, setState] = useState<ChatState>({ kind: 'idle' });
  const [message, setMessage] = useState('');
  const [section, setSection] = useState<Section>('chat');
  const [workspace, setWorkspace] = useState<WorkspaceData | null>(null);
  const [workspaceLoading, setWorkspaceLoading] = useState(false);
  const [workspaceError, setWorkspaceError] = useState<string | null>(null);
  const [detail, setDetail] = useState<DetailState>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [manualSale, setManualSale] = useState(false);

  async function loadWorkspace(currentSection = section) {
    if (currentSection === 'chat' || !accountLinked) return;
    setWorkspaceLoading(true);
    setWorkspaceError(null);
    try {
      const response = await fetch(`/api/workspace?section=${currentSection}`);
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? 'تعذر تحميل البيانات.');
      setWorkspace(body as WorkspaceData);
    } catch (error) {
      setWorkspaceError(error instanceof Error ? error.message : 'تعذر تحميل البيانات.');
    } finally {
      setWorkspaceLoading(false);
    }
  }

  useEffect(() => {
    if (section === 'chat' || !accountLinked) return;
    let cancelled = false;
    setWorkspaceLoading(true);
    setWorkspaceError(null);
    setDetail(null);
    setManualSale(false);
    fetch(`/api/workspace?section=${section}`)
      .then(async (response) => {
        const body = await response.json();
        if (!response.ok) throw new Error(body.error ?? 'تعذر تحميل البيانات.');
        return body as WorkspaceData;
      })
      .then((body) => { if (!cancelled) setWorkspace(body); })
      .catch((error) => { if (!cancelled) setWorkspaceError(error instanceof Error ? error.message : 'تعذر تحميل البيانات.'); })
      .finally(() => { if (!cancelled) setWorkspaceLoading(false); });
    return () => { cancelled = true; };
  }, [section, accountLinked]);

  async function openDetail(kind: 'customer' | 'transaction', id: unknown) {
    if (!id) return;
    setDetailLoading(true);
    setWorkspaceError(null);
    setManualSale(false);
    try {
      const response = await fetch(`/api/workspace?detail=${kind}&id=${encodeURIComponent(String(id))}`);
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? 'تعذر تحميل التفاصيل.');
      setDetail({ kind, value: asRecord(body.value) });
    } catch (error) {
      setWorkspaceError(error instanceof Error ? error.message : 'تعذر تحميل التفاصيل.');
    } finally {
      setDetailLoading(false);
    }
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const value = message.trim();
    if (!value || !accountLinked) return;
    setState({ kind: 'loading', message: value });
    const response = await fetch('/api/agent/interpret', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ message: value }) });
    const body = await response.json();
    if (!response.ok) { setState({ kind: 'error', message: body.error ?? 'تعذر فهم العملية.' }); return; }
    if (body.status === 'needs_clarification') { setState({ kind: 'clarification', value: body }); return; }
    setState({ kind: 'draft', value: body });
  }

  async function confirm() {
    if (state.kind !== 'draft') return;
    const response = await fetch('/api/sales/confirm', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(state.value.draft) });
    const body = await response.json();
    if (!response.ok) { setState({ kind: 'error', message: body.error ?? 'تعذر اعتماد العملية.' }); return; }
    setState({ kind: 'success', transactionNo: body.transaction.transaction_no });
    setMessage('');
  }

  function renderCustomerDetail(value: Record<string, unknown>) {
    const customer = asRecord(value.customer);
    const balances = asRows(value.balances);
    const ledger = asRows(value.ledger);
    const customerId = String(customer.customer_id ?? '');

    return <div className="detail-stack">
      <div className="detail-hero">
        <button className="back-button" onClick={() => setDetail(null)}>رجوع</button>
        <div><span className="eyebrow">ملف العميل</span><h2>{String(customer.display_name ?? 'عميل')}</h2><p>{customer.phone ? String(customer.phone) : 'بدون رقم هاتف'} · آخر حركة {formatDate(customer.last_transaction_at)}</p></div>
        <div className="hero-stat"><small>إجمالي المبيعات</small><b>{formatNumber(customer.total_sales_amount)}</b></div>
      </div>
      <div className="balance-grid">{balances.length ? balances.map((row) => <div className="balance-card" key={String(row.currency)}><span>{String(row.currency)}</span><b>{formatNumber(row.balance)}</b><small>الرصيد الحالي</small></div>) : <div className="balance-card"><span>الحساب</span><b>0</b><small>لا توجد أرصدة معلقة</small></div>}</div>
      {customerId && <CustomerActionPanel customerId={customerId} balances={balances} onReceiptCreated={() => openDetail('customer', customerId)} />}
      <div className="surface">
        <div className="surface-head"><div><strong>حركة الحساب</strong><p>أحدث قيود دفتر العميل.</p></div><span className="count-pill">{ledger.length} قيد</span></div>
        <div className="data-list">{ledger.map((row, index) => <div className="data-row static" key={`${row.entry_datetime}-${index}`}><div><b>{String(row.description ?? row.transaction_no ?? 'حركة حساب')}</b><small>{formatDate(row.entry_datetime)} · {String(row.currency ?? '')}</small></div><div className="row-meta"><b>{Number(row.debit_amount ?? 0) > 0 ? `+${formatNumber(row.debit_amount)}` : `-${formatNumber(row.credit_amount)}`}</b><small>الرصيد {formatNumber(row.balance_after)}</small></div></div>)}</div>
      </div>
    </div>;
  }

  function renderOperationalSection() {
    if (manualSale && section === 'transactions') return <ManualSalePanel businessId={businessId} onCancel={() => setManualSale(false)} onCreated={(id) => { void loadWorkspace('transactions'); void openDetail('transaction', id); }} />;
    if (detailLoading) return <div className="surface empty-state"><strong>جارٍ تحميل التفاصيل…</strong></div>;
    if (detail?.kind === 'customer') return renderCustomerDetail(detail.value);
    if (detail?.kind === 'transaction') return <TransactionDetailPanel value={detail.value} onBack={() => setDetail(null)} onOpenCustomer={(id) => void openDetail('customer', id)} onCancelled={async (id) => { await loadWorkspace('transactions'); await openDetail('transaction', id); }} />;
    if (workspaceLoading) return <div className="surface empty-state"><strong>جارٍ تحميل البيانات…</strong></div>;
    if (workspaceError) return <div className="surface empty-state"><strong>تعذر تحميل البيانات</strong><p>{workspaceError}</p></div>;
    if (section === 'customers') return <CustomersPanel rows={workspace?.rows ?? []} onOpen={(id) => void openDetail('customer', id)} />;
    if (section === 'transactions') return <TransactionsPanel rows={workspace?.rows ?? []} onOpen={(id) => void openDetail('transaction', id)} />;
    if (section === 'debts') return <DebtsPanel initialRows={workspace?.rows ?? []} onOpenCustomer={(id) => void openDetail('customer', id)} />;
    if (section === 'reports') return <ReportsPanel initialOverview={workspace?.rows ?? []} initialTopProducts={workspace?.topProducts ?? []} />;
    return null;
  }

  function changeSection(next: Section) {
    setSection(next);
    setDetail(null);
    setManualSale(false);
  }

  return <main className="workspace">
    <aside className="sidebar"><div className="brand"><span className="brand-mark small">B</span><div><strong>باحكم</strong><small>المساعد التشغيلي</small></div></div><nav>{tabs.map((tab) => <button key={tab.id} className={section === tab.id ? 'active' : ''} onClick={() => changeSection(tab.id)}>{tab.label}</button>)}</nav><div className="user-card"><span>{displayName}</span><small>{roleLabel}</small></div></aside>
    <section className="chat">
      <MobileNavigation section={section} onChange={changeSection} />
      <header><div><h1>{sectionTitle(section)}</h1><p>{accountLinked ? businessLabel : 'تم تسجيل الدخول، لكن يلزم ربط الحساب بمستخدم IBEX قبل تنفيذ العمليات المالية.'}</p></div><span className={accountLinked ? 'status ok' : 'status warn'}>{accountLinked ? 'جاهز' : 'بحاجة إلى ربط'}</span></header>
      {section === 'chat' ? <>
        <div className="conversation">{state.kind === 'idle' && <div className="welcome-card"><strong>ابدأ بأمر طبيعي</strong><p>مثال: بع كيلو سمرة SI للزبون العام بـ 20000 YER نقدًا.</p><p className="muted">سأحوّل الأمر إلى مسودة، ولن أسجل الحركة قبل موافقتك.</p></div>}{state.kind === 'loading' && <div className="welcome-card"><strong>أحلل العملية…</strong><p>{state.message}</p></div>}{state.kind === 'clarification' && <div className="welcome-card"><strong>أحتاج تحديدًا بسيطًا</strong><p>{state.value.question}</p>{state.value.candidates.map((c) => <div key={c.id} className="candidate">{c.label}</div>)}</div>}{state.kind === 'draft' && <div className="welcome-card draft-card"><strong>مسودة فاتورة مبيعات</strong><div className="draft-grid"><span>العميل</span><b>{state.value.preview.customer_name}</b><span>الصنف</span><b>{state.value.preview.product_name}</b><span>الكمية</span><b>{state.value.preview.quantity} {state.value.preview.unit_name}</b><span>سعر الوحدة</span><b>{state.value.preview.unit_price} {state.value.preview.currency}</b><span>الإجمالي</span><b>{state.value.preview.total_amount} {state.value.preview.currency}</b><span>المدفوع</span><b>{state.value.preview.paid_amount} {state.value.preview.currency}</b><span>المتبقي</span><b>{state.value.preview.remaining_amount} {state.value.preview.currency}</b></div><div className="draft-actions"><button className="secondary" onClick={() => setState({ kind: 'idle' })}>إلغاء</button><button onClick={confirm}>اعتماد العملية</button></div></div>}{state.kind === 'success' && <div className="welcome-card"><strong>تم اعتماد العملية</strong><p>رقم العملية: <b>{state.transactionNo}</b></p><button onClick={() => setState({ kind: 'idle' })}>عملية جديدة</button></div>}{state.kind === 'error' && <div className="welcome-card"><strong>تعذر إكمال الطلب</strong><p>{state.message}</p><button onClick={() => setState({ kind: 'idle' })}>إعادة المحاولة</button></div>}</div>
        <form className="composer" onSubmit={submit}><textarea value={message} onChange={(event) => setMessage(event.target.value)} placeholder="اكتب العملية أو السؤال هنا…" rows={2} disabled={!accountLinked} /><button disabled={!accountLinked || state.kind === 'loading'} type="submit">إرسال</button></form>
      </> : <>
        <div className="operations-toolbar"><div><b>{manualSale ? 'فاتورة مبيعات جديدة' : detail ? 'عرض التفاصيل' : sectionTitle(section)}</b><small>{manualSale ? 'مسار يدوي كامل مع مراجعة قبل الاعتماد' : detail ? 'إجراءات وقراءة تشغيلية من بيانات IBEX الفعلية' : 'واجهة تشغيل مباشرة للبيانات الفعلية في IBEX'}</small></div>{section === 'transactions' && !detail && !manualSale && <button className="toolbar-primary" onClick={() => setManualSale(true)}>+ فاتورة جديدة</button>}</div>
        <div className="operations-content">{renderOperationalSection()}</div>
      </>}
    </section>
  </main>;
}
