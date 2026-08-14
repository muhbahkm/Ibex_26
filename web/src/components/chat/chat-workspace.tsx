'use client';

import { FormEvent, useState } from 'react';

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

export function ChatWorkspace({ displayName, roleLabel, accountLinked, businessLabel }: Props) {
  const [state, setState] = useState<ChatState>({ kind: 'idle' });
  const [message, setMessage] = useState('');

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

  return (
    <main className="workspace">
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark small">B</span><div><strong>باحكم</strong><small>المساعد التشغيلي</small></div></div>
        <nav><button className="active">محادثة جديدة</button><button>العملاء</button><button>العمليات</button><button>الديون</button><button>التقارير</button></nav>
        <div className="user-card"><span>{displayName}</span><small>{roleLabel}</small></div>
      </aside>

      <section className="chat">
        <header><div><h1>كيف أساعدك في إدارة العمل؟</h1><p>{accountLinked ? businessLabel : 'تم تسجيل الدخول، لكن يلزم ربط الحساب بمستخدم IBEX قبل تنفيذ العمليات المالية.'}</p></div><span className={accountLinked ? 'status ok' : 'status warn'}>{accountLinked ? 'جاهز' : 'بحاجة إلى ربط'}</span></header>

        <div className="conversation">
          {state.kind === 'idle' && <div className="welcome-card"><strong>ابدأ بأمر طبيعي</strong><p>مثال: بع كيلو سمرة SI للزبون العام بـ 20000 YER نقدًا.</p><p className="muted">سأحوّل الأمر إلى مسودة، ولن أسجل الحركة قبل موافقتك.</p></div>}
          {state.kind === 'loading' && <div className="welcome-card"><strong>أحلل العملية…</strong><p>{state.message}</p></div>}
          {state.kind === 'clarification' && <div className="welcome-card"><strong>أحتاج تحديدًا بسيطًا</strong><p>{state.value.question}</p>{state.value.candidates.map((c) => <div key={c.id} className="candidate">{c.label}</div>)}</div>}
          {state.kind === 'draft' && <div className="welcome-card draft-card"><strong>مسودة فاتورة مبيعات</strong><div className="draft-grid"><span>العميل</span><b>{state.value.preview.customer_name}</b><span>الصنف</span><b>{state.value.preview.product_name}</b><span>الكمية</span><b>{state.value.preview.quantity} {state.value.preview.unit_name}</b><span>سعر الوحدة</span><b>{state.value.preview.unit_price} {state.value.preview.currency}</b><span>الإجمالي</span><b>{state.value.preview.total_amount} {state.value.preview.currency}</b><span>المدفوع</span><b>{state.value.preview.paid_amount} {state.value.preview.currency}</b><span>المتبقي</span><b>{state.value.preview.remaining_amount} {state.value.preview.currency}</b></div><div className="draft-actions"><button className="secondary" onClick={() => setState({ kind: 'idle' })}>إلغاء</button><button onClick={confirm}>اعتماد العملية</button></div></div>}
          {state.kind === 'success' && <div className="welcome-card"><strong>تم اعتماد العملية</strong><p>رقم العملية: <b>{state.transactionNo}</b></p><button onClick={() => setState({ kind: 'idle' })}>عملية جديدة</button></div>}
          {state.kind === 'error' && <div className="welcome-card"><strong>تعذر إكمال الطلب</strong><p>{state.message}</p><button onClick={() => setState({ kind: 'idle' })}>إعادة المحاولة</button></div>}
        </div>

        <form className="composer" onSubmit={submit}><textarea value={message} onChange={(e) => setMessage(e.target.value)} placeholder="اكتب العملية أو السؤال هنا…" rows={2} disabled={!accountLinked} /><button disabled={!accountLinked || state.kind === 'loading'} type="submit">إرسال</button></form>
      </section>
    </main>
  );
}
