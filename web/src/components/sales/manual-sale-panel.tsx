'use client';

import { FormEvent, useEffect, useMemo, useRef, useState } from 'react';

type Currency = 'YER' | 'SAR' | 'USD';
type PaymentStatus = 'cash' | 'credit' | 'partial';
type Product = { id: string; product_name: string; category: string | null; default_unit_id: string | null; default_unit_name: string | null; default_sale_price: number; default_currency: Currency };
type Customer = { id: string; display_name: string; phone: string | null; is_general_customer: boolean };
type Unit = { id: string; unit_name: string; unit_code: string | null };
type CashRow = { cash_account_id: string; currency: Currency; is_active: boolean };
type PendingSale = { draft: Record<string, unknown>; summary: { customer: string; product: string; unit: string; quantity: number; unitPrice: number; total: number; paid: number; remaining: number; currency: Currency; paymentStatus: PaymentStatus } };

type Props = {
  businessId: string;
  onCancel: () => void;
  onCreated: (transactionId: string) => void;
};

function money(value: number) {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(value);
}

async function lookup(kind: string, query = '', currency?: Currency) {
  const params = new URLSearchParams({ kind });
  if (query) params.set('q', query);
  if (currency) params.set('currency', currency);
  const response = await fetch(`/api/sales/options?${params.toString()}`);
  const body = await response.json();
  if (!response.ok) throw new Error(body.error ?? 'LOOKUP_FAILED');
  return body;
}

export function ManualSalePanel({ businessId, onCancel, onCreated }: Props) {
  const submitLock = useRef(false);
  const [productQuery, setProductQuery] = useState('');
  const [customerQuery, setCustomerQuery] = useState('زبون عام');
  const [unitQuery, setUnitQuery] = useState('');
  const [products, setProducts] = useState<Product[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [units, setUnits] = useState<Unit[]>([]);
  const [product, setProduct] = useState<Product | null>(null);
  const [customer, setCustomer] = useState<Customer | null>(null);
  const [unit, setUnit] = useState<Unit | null>(null);
  const [quantity, setQuantity] = useState('1');
  const [unitPrice, setUnitPrice] = useState('');
  const [currency, setCurrency] = useState<Currency>('YER');
  const [paymentStatus, setPaymentStatus] = useState<PaymentStatus>('cash');
  const [paidAmount, setPaidAmount] = useState('');
  const [discount, setDiscount] = useState('0');
  const [notes, setNotes] = useState('');
  const [pending, setPending] = useState<PendingSale | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const timer = window.setTimeout(() => {
      lookup('products', productQuery).then((body) => { if (active) setProducts(Array.isArray(body.rows) ? body.rows : []); }).catch(() => { if (active) setProducts([]); });
    }, 180);
    return () => { active = false; window.clearTimeout(timer); };
  }, [productQuery]);

  useEffect(() => {
    let active = true;
    const timer = window.setTimeout(() => {
      lookup('customers', customerQuery).then((body) => {
        if (!active) return;
        const rows = Array.isArray(body.rows) ? body.rows as Customer[] : [];
        setCustomers(rows);
        if (!customer && rows.length === 1 && rows[0].is_general_customer) setCustomer(rows[0]);
      }).catch(() => { if (active) setCustomers([]); });
    }, 180);
    return () => { active = false; window.clearTimeout(timer); };
  }, [customerQuery, customer]);

  useEffect(() => {
    let active = true;
    const timer = window.setTimeout(() => {
      lookup('units', unitQuery).then((body) => { if (active) setUnits(Array.isArray(body.rows) ? body.rows : []); }).catch(() => { if (active) setUnits([]); });
    }, 180);
    return () => { active = false; window.clearTimeout(timer); };
  }, [unitQuery]);

  useEffect(() => {
    if (!product) return;
    setUnitPrice(String(Number(product.default_sale_price ?? 0)));
    setCurrency(product.default_currency);
    if (product.default_unit_id && product.default_unit_name) {
      setUnit({ id: product.default_unit_id, unit_name: product.default_unit_name, unit_code: null });
      setUnitQuery(product.default_unit_name);
    }
    setPending(null);
  }, [product]);

  const total = useMemo(() => {
    const q = Number(quantity);
    const price = Number(unitPrice);
    const d = Number(discount);
    if (![q, price, d].every(Number.isFinite)) return 0;
    return Math.max((q * price) - d, 0);
  }, [quantity, unitPrice, discount]);

  const calculatedPaid = paymentStatus === 'cash' ? total : paymentStatus === 'credit' ? 0 : Number(paidAmount || 0);

  async function review(event: FormEvent) {
    event.preventDefault();
    setNotice(null);
    setPending(null);

    const q = Number(quantity);
    const price = Number(unitPrice);
    const d = Number(discount || 0);
    const paid = calculatedPaid;
    if (!product) return setNotice('اختر الصنف أولًا.');
    if (!customer) return setNotice('اختر العميل أولًا.');
    if (!unit) return setNotice('اختر وحدة البيع.');
    if (!Number.isFinite(q) || q <= 0) return setNotice('الكمية يجب أن تكون أكبر من صفر.');
    if (!Number.isFinite(price) || price < 0) return setNotice('سعر الوحدة غير صحيح.');
    if (!Number.isFinite(d) || d < 0 || d > q * price) return setNotice('الخصم غير صحيح.');
    if (!Number.isFinite(paid) || paid < 0 || paid > total) return setNotice('المبلغ المدفوع غير صحيح.');
    if (paymentStatus === 'partial' && (paid <= 0 || paid >= total)) return setNotice('الدفع الجزئي يجب أن يكون أكبر من صفر وأقل من الإجمالي.');

    setBusy(true);
    try {
      let cash: CashRow | null = null;
      if (paid > 0) {
        const body = await lookup('cash', '', currency);
        cash = body.row ?? null;
        if (!cash?.cash_account_id) throw new Error('CASH_ACCOUNT_NOT_FOUND');
      }

      const draft = {
        business_id: businessId,
        customer_id: customer.id,
        party_name: customer.display_name,
        party_phone: customer.phone ?? undefined,
        currency,
        payment_status: paymentStatus,
        paid_amount: paid,
        discount_amount: d,
        cash_account_id: cash?.cash_account_id,
        notes: notes.trim() || undefined,
        items: [{
          product_id: product.id,
          product_name: product.product_name,
          unit_id: unit.id,
          unit_name: unit.unit_name,
          quantity: q,
          unit_price: price,
          category: product.category ?? undefined,
        }],
      };

      setPending({
        draft,
        summary: {
          customer: customer.display_name,
          product: product.product_name,
          unit: unit.unit_name,
          quantity: q,
          unitPrice: price,
          total,
          paid,
          remaining: Math.max(total - paid, 0),
          currency,
          paymentStatus,
        },
      });
    } catch (error) {
      setNotice(error instanceof Error && error.message === 'CASH_ACCOUNT_NOT_FOUND' ? 'لا يوجد صندوق نشط لهذه العملة.' : 'تعذر تجهيز الفاتورة للمراجعة.');
    } finally {
      setBusy(false);
    }
  }

  async function confirm() {
    if (!pending || submitLock.current) return;
    submitLock.current = true;
    setBusy(true);
    setNotice(null);
    try {
      const response = await fetch('/api/sales/confirm', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(pending.draft) });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? 'SALE_CREATE_FAILED');
      setNotice(`تم اعتماد الفاتورة ${body.transaction.transaction_no} بنجاح.`);
      setPending(null);
      onCreated(String(body.transaction.transaction_id));
    } catch {
      setNotice('تعذر اعتماد الفاتورة. لم يتم تسجيل أي حركة جديدة.');
    } finally {
      submitLock.current = false;
      setBusy(false);
    }
  }

  return <section className="detail-stack manual-sale">
    <div className="detail-hero">
      <button className="back-button" onClick={onCancel}>رجوع</button>
      <div><span className="eyebrow">إجراء تشغيلي</span><h2>فاتورة مبيعات جديدة</h2><p>أنشئ الفاتورة يدويًا دون استخدام المحادثة، ثم راجعها قبل الاعتماد.</p></div>
      <div className="hero-stat"><small>الإجمالي الحالي</small><b>{money(total)} {currency}</b></div>
    </div>

    {notice && <div className="inline-notice">{notice}</div>}

    <form className="surface action-form manual-sale-form" onSubmit={review}>
      <label className="wide"><span>العميل</span><input value={customerQuery} onChange={(event) => { setCustomerQuery(event.target.value); setCustomer(null); setPending(null); }} placeholder="ابحث باسم العميل أو رقمه" /><div className="lookup-results">{!customer && customers.map((row) => <button type="button" key={row.id} onClick={() => { setCustomer(row); setCustomerQuery(row.display_name); }}>{row.display_name}<small>{row.phone ?? 'بدون رقم'}</small></button>)}</div></label>
      <label className="wide"><span>الصنف</span><input value={productQuery} onChange={(event) => { setProductQuery(event.target.value); setProduct(null); setPending(null); }} placeholder="ابحث عن الصنف" /><div className="lookup-results">{!product && products.map((row) => <button type="button" key={row.id} onClick={() => { setProduct(row); setProductQuery(row.product_name); }}>{row.product_name}<small>{money(Number(row.default_sale_price))} {row.default_currency}</small></button>)}</div></label>
      <label><span>الوحدة</span><input value={unitQuery} onChange={(event) => { setUnitQuery(event.target.value); setUnit(null); setPending(null); }} placeholder="الوحدة" /><div className="lookup-results compact">{!unit && units.map((row) => <button type="button" key={row.id} onClick={() => { setUnit(row); setUnitQuery(row.unit_name); }}>{row.unit_name}</button>)}</div></label>
      <label><span>الكمية</span><input inputMode="decimal" value={quantity} onChange={(event) => { setQuantity(event.target.value); setPending(null); }} /></label>
      <label><span>سعر الوحدة</span><input inputMode="decimal" value={unitPrice} onChange={(event) => { setUnitPrice(event.target.value); setPending(null); }} /></label>
      <label><span>العملة</span><select value={currency} onChange={(event) => { setCurrency(event.target.value as Currency); setPending(null); }}><option value="YER">YER</option><option value="SAR">SAR</option><option value="USD">USD</option></select></label>
      <label><span>حالة السداد</span><select value={paymentStatus} onChange={(event) => { setPaymentStatus(event.target.value as PaymentStatus); setPending(null); }}><option value="cash">نقد</option><option value="credit">آجل</option><option value="partial">جزئي</option></select></label>
      {paymentStatus === 'partial' && <label><span>المدفوع الآن</span><input inputMode="decimal" value={paidAmount} onChange={(event) => { setPaidAmount(event.target.value); setPending(null); }} /></label>}
      <label><span>الخصم</span><input inputMode="decimal" value={discount} onChange={(event) => { setDiscount(event.target.value); setPending(null); }} /></label>
      <label className="wide"><span>ملاحظات</span><input value={notes} onChange={(event) => { setNotes(event.target.value); setPending(null); }} placeholder="اختياري" /></label>
      <div className="sale-summary wide"><span>الإجمالي <b>{money(total)} {currency}</b></span><span>المدفوع <b>{money(calculatedPaid)} {currency}</b></span><span>المتبقي <b>{money(Math.max(total - calculatedPaid, 0))} {currency}</b></span></div>
      <div className="action-submit wide"><button type="submit" disabled={busy}>{busy ? 'جارٍ التحقق…' : 'مراجعة الفاتورة'}</button></div>
    </form>

    {pending && <div className="surface review-panel">
      <div className="surface-head"><div><strong>مراجعة قبل الاعتماد</strong><p>لن تُسجّل الحركة إلا بعد الضغط على اعتماد.</p></div><span className="count-pill">{pending.summary.paymentStatus === 'cash' ? 'نقد' : pending.summary.paymentStatus === 'credit' ? 'آجل' : 'جزئي'}</span></div>
      <div className="draft-grid"><span>العميل</span><b>{pending.summary.customer}</b><span>الصنف</span><b>{pending.summary.product}</b><span>الكمية</span><b>{pending.summary.quantity} {pending.summary.unit}</b><span>سعر الوحدة</span><b>{money(pending.summary.unitPrice)} {pending.summary.currency}</b><span>الإجمالي</span><b>{money(pending.summary.total)} {pending.summary.currency}</b><span>المدفوع</span><b>{money(pending.summary.paid)} {pending.summary.currency}</b><span>المتبقي</span><b>{money(pending.summary.remaining)} {pending.summary.currency}</b></div>
      <div className="draft-actions review-actions"><button className="secondary" type="button" onClick={() => setPending(null)} disabled={busy}>تعديل</button><button type="button" onClick={confirm} disabled={busy}>{busy ? 'جارٍ الاعتماد…' : 'اعتماد الفاتورة'}</button></div>
    </div>}
  </section>;
}
