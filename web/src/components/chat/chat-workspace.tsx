'use client';

import { FormEvent, useEffect, useMemo, useState } from 'react';

type Props = {
  displayName: string;
  roleLabel: string;
  accountLinked: boolean;
  businessLabel: string;
};

type DraftReady = {
  status: 'draft_ready';
  source_message: string;
  draft: Record<string, unknown>;
  preview: {
    customer_name: string;
    product_name: string;
    unit_name: string;
    quantity: number;
    unit_price: number;
    currency: string;
    total_amount: number;
    paid_amount: number;
    remaining_amount: number;
  };
};

type Clarification = {
  status: 'needs_clarification';
  question: string;
  candidates: { id: string; label: string }[];
};

type ChatState =
  | { kind: 'idle' }
  | { kind: 'loading'; message: string }
  | { kind: 'draft'; value: DraftReady }
  | { kind: 'clarification'; value: Clarification }
  | { kind: 'success'; transactionNo: string }
  | { kind: 'error'; message: string };

type Section = 'chat' | 'customers' | 'transactions' | 'debts' | 'reports';
type WorkspaceData = { section: string; rows?: Record<string, unknown>[] };

const tabs: { id: Section; label: string }[] = [
  { id: 'chat', label: 'محادثة جديدة' },
  { id: 'customers', label: 'العملاء' },
  { id: 'transactions', label: 'العمليات' },
  { id: 'debts', label: 'الديون' },
  { id: 'reports', label: 'التقارير' },
];

function formatNumber(value: unknown) {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(Number(value ?? 0));
}

function formatDate(value: unknown) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('ar-YE', { dateStyle: 'medium' }).format(new Date(String(value)));
}

function sectionTitle(section: Section) {
  if (section === 'customers') return 'العملاء والحسابات';
  if (section === 'transactions') return 'سجل العمليات';
  if (section === 'debts') return 'متابعة الديون';
  if (section === 'reports') return 'التقارير والمؤشرات';
  return 'كيف أساعدك في إدارة العمل؟';
}

export function ChatWorkspace({ displayName, roleLabel, accountLinked, businessLabel }: Props) {
  const [state, setState] = useState<ChatState>({ kind: 'idle' });
  const [message, setMessage] = useState('');
  const [section, setSection] = useState<Section>('chat');
  const [workspace, setWorkspace] = useState<WorkspaceData | null>(null);
  const [workspaceLoading, setWorkspaceLoading] = useState(false);
  const [workspaceError, setWorkspaceError] = useState<string | null>(null);
  const [query, setQuery] = useState('');

  useEffect(() => {
    if (section === 'chat' || !accountLinked) return;
    let cancelled = false;
    setWorkspaceLoading(true);
    setWorkspaceError(null);
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

  const filteredRows = useMemo(() => {
    const rows = workspace?.rows ?? [];
    const normalized = query.trim().toLocaleLowerCase('ar');
    if (!normalized) return rows;
    return rows.filter((row) => Object.values(row).some((value) => String(value ?? '').toLocaleLowerCase('ar').includes(normalized)));
  }, [workspace, query]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const value = message.trim();
    if (!value || !accountLinked) return;
    setState({ kind: 'loading', message: value });

    const response = await fetch('/api/agent/interpret', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ message: value }),
    });
    const body = await response.json();

    if (!response.ok) {
      setState({ kind: 'error', message: body.error ?? 'تعذر فهم العملية.' });
      return;
    }
    if (body.status === 'needs_clarification') {
      setState({ kind: 'clarification', value: body });
      return;
    }
    setState({ kind: 'draft', value: body });
  }

  async function confirm() {
    if (state.kind !== 'draft') return;
    const response = await fetch('/api/sales/confirm', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(state.value.draft),
    });
    const body = await response.json();
    if (!response.ok) {
      setState({ kind: 'error', message: body.error ?? 'تعذر اعتماد العملية.' });
      return;
    }
    setState({ kind: 'success', transactionNo: body.transaction.transaction_no });
    setMessage('');
  }

  function renderOperationalSection() {
    if (workspaceLoading) return <div className="surface empty-state"><strong>جارٍ تحميل البيانات…</strong></div>;
    if (workspaceError) return <div className="surface empty-state"><strong>تعذر تحميل البيانات</strong><p>{workspaceError}</p></div>;

    if (section === 'customers') {
      return <div className="surface"><div className="surface-head"><div><strong>حسابات العملاء</strong><p>الأرصدة مفصولة حسب العملة، مع آخر حركة ظاهرة.</p></div><span className="count-pill">{filteredRows.length} حساب</span></div><div className="data-list">{filteredRows.map((row) => <button className="data-row" key={`${row.customer_id}-${row.currency}`}><div><b>{String(row.display_name ?? 'بدون اسم')}</b><small>{row.phone ? String(row.phone) : 'لا يوجد رقم هاتف'}</small></div><div className="row-meta"><b>{formatNumber(row.balance)} {String(row.currency)}</b><small>آخر حركة {formatDate(row.last_transaction_at)}</small></div></button>)}</div></div>;
    }

    if (section === 'transactions') {
      return <div className="surface"><div className="surface-head"><div><strong>آخر العمليات</strong><p>عرض تشغيلي مباشر للحركات مع حالة السداد والربحية.</p></div><span className="count-pill">{filteredRows.length} عملية</span></div><div className="data-list">{filteredRows.map((row) => <button className="data-row" key={String(row.id)}><div><b>{String(row.transaction_no)}</b><small>{String(row.customer_name ?? 'بدون طرف')} · {formatDate(row.transaction_datetime)}</small></div><div className="row-meta"><b>{formatNumber(row.total_amount)} {String(row.currency)}</b><small>{String(row.payment_status)} · ربح {formatNumber(row.estimated_profit)}</small></div></button>)}</div></div>;
    }

    if (section === 'debts') {
      return <div className="surface"><div className="surface-head"><div><strong>الديون المتأخرة</strong><p>العملاء الذين تجاوزت آخر حركة على حسابهم 30 يومًا.</p></div><span className="count-pill danger">{filteredRows.length} متابعة</span></div><div className="data-list">{filteredRows.map((row) => <button className="data-row" key={`${row.customer_id}-${row.currency}`}><div><b>{String(row.display_name)}</b><small>{row.phone ? String(row.phone) : 'بدون رقم هاتف'} · آخر نشاط {formatDate(row.last_ledger_activity_at)}</small></div><div className="row-meta"><b>{formatNumber(row.balance)} {String(row.currency)}</b><small>{formatNumber(row.days_since_last_activity)} يوم دون حركة</small></div></button>)}</div></div>;
    }

    if (section === 'reports') {
      return <div className="report-grid">{filteredRows.map((row) => <article className="metric-card" key={String(row.currency)}><div className="metric-title"><strong>{String(row.currency)}</strong><span>آخر 30 يومًا</span></div><div className="metric-main">{formatNumber(row.sales_total)}</div><small>إجمالي المبيعات</small><div className="metric-pairs"><div><span>الربح التقديري</span><b>{formatNumber(row.estimated_profit_total)}</b></div><div><span>المتبقي</span><b>{formatNumber(row.remaining_total)}</b></div><div><span>التحصيل</span><b>{formatNumber(row.collected_total)}</b></div><div><span>عدد المبيعات</span><b>{formatNumber(row.sales_count)}</b></div></div></article>)}</div>;
    }
    return null;
  }

  return (
    <main className="workspace">
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark small">B</span><div><strong>باحكم</strong><small>المساعد التشغيلي</small></div></div>
        <nav>{tabs.map((tab) => <button key={tab.id} className={section === tab.id ? 'active' : ''} onClick={() => { setSection(tab.id); setQuery(''); }}>{tab.label}</button>)}</nav>
        <div className="user-card"><span>{displayName}</span><small>{roleLabel}</small></div>
      </aside>

      <section className="chat">
        <header><div><h1>{sectionTitle(section)}</h1><p>{accountLinked ? businessLabel : 'تم تسجيل الدخول، لكن يلزم ربط الحساب بمستخدم IBEX قبل تنفيذ العمليات المالية.'}</p></div><span className={accountLinked ? 'status ok' : 'status warn'}>{accountLinked ? 'جاهز' : 'بحاجة إلى ربط'}</span></header>

        {section === 'chat' ? <>
          <div className="conversation">
            {state.kind === 'idle' && <div className="welcome-card"><strong>ابدأ بأمر طبيعي</strong><p>مثال: بع كيلو سمرة SI للزبون العام بـ 20000 YER نقدًا.</p><p className="muted">سأحوّل الأمر إلى مسودة، ولن أسجل الحركة قبل موافقتك.</p></div>}
            {state.kind === 'loading' && <div className="welcome-card"><strong>أحلل العملية…</strong><p>{state.message}</p></div>}
            {state.kind === 'clarification' && <div className="welcome-card"><strong>أحتاج تحديدًا بسيطًا</strong><p>{state.value.question}</p>{state.value.candidates.map((c) => <div key={c.id} className="candidate">{c.label}</div>)}</div>}
            {state.kind === 'draft' && <div className="welcome-card draft-card"><strong>مسودة فاتورة مبيعات</strong><div className="draft-grid"><span>العميل</span><b>{state.value.preview.customer_name}</b><span>الصنف</span><b>{state.value.preview.product_name}</b><span>الكمية</span><b>{state.value.preview.quantity} {state.value.preview.unit_name}</b><span>سعر الوحدة</span><b>{state.value.preview.unit_price} {state.value.preview.currency}</b><span>الإجمالي</span><b>{state.value.preview.total_amount} {state.value.preview.currency}</b><span>المدفوع</span><b>{state.value.preview.paid_amount} {state.value.preview.currency}</b><span>المتبقي</span><b>{state.value.preview.remaining_amount} {state.value.preview.currency}</b></div><div className="draft-actions"><button className="secondary" onClick={() => setState({ kind: 'idle' })}>إلغاء</button><button onClick={confirm}>اعتماد العملية</button></div></div>}
            {state.kind === 'success' && <div className="welcome-card"><strong>تم اعتماد العملية</strong><p>رقم العملية: <b>{state.transactionNo}</b></p><button onClick={() => setState({ kind: 'idle' })}>عملية جديدة</button></div>}
            {state.kind === 'error' && <div className="welcome-card"><strong>تعذر إكمال الطلب</strong><p>{state.message}</p><button onClick={() => setState({ kind: 'idle' })}>إعادة المحاولة</button></div>}
          </div>
          <form className="composer" onSubmit={submit}><textarea value={message} onChange={(e) => setMessage(e.target.value)} placeholder="اكتب العملية أو السؤال هنا…" rows={2} disabled={!accountLinked} /><button disabled={!accountLinked || state.kind === 'loading'} type="submit">إرسال</button></form>
        </> : <>
          <div className="operations-toolbar"><div><b>{sectionTitle(section)}</b><small>واجهة تشغيل مباشرة للبيانات الفعلية في IBEX</small></div><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="بحث سريع…" /></div>
          <div className="operations-content">{renderOperationalSection()}</div>
        </>}
      </section>
    </main>
  );
}
