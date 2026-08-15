'use client';

import { FormEvent, useMemo, useState } from 'react';

type Currency = '' | 'YER' | 'SAR' | 'USD';
type Row = Record<string, unknown>;

type Props = {
  initialOverview: Row[];
  initialTopProducts: Row[];
};

function formatNumber(value: unknown) {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(Number(value ?? 0));
}

export function ReportsPanel({ initialOverview, initialTopProducts }: Props) {
  const [overview, setOverview] = useState<Row[]>(initialOverview);
  const [topProducts, setTopProducts] = useState<Row[]>(initialTopProducts);
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [currency, setCurrency] = useState<Currency>('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rangeLabel, setRangeLabel] = useState('آخر 30 يومًا');

  const totals = useMemo(() => overview.reduce<{ sales: number; profit: number; remaining: number; collected: number }>((sum, row) => ({
    sales: sum.sales + Number(row.sales_total ?? 0),
    profit: sum.profit + Number(row.estimated_profit_total ?? 0),
    remaining: sum.remaining + Number(row.remaining_total ?? 0),
    collected: sum.collected + Number(row.collected_total ?? 0),
  }), { sales: 0, profit: 0, remaining: 0, collected: 0 }), [overview]);

  async function applyFilters(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const params = new URLSearchParams();
      if (dateFrom) params.set('dateFrom', dateFrom);
      if (dateTo) params.set('dateTo', dateTo);
      if (currency) params.set('currency', currency);
      const response = await fetch(`/api/reports?${params.toString()}`);
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? 'REPORT_READ_FAILED');
      setOverview(Array.isArray(body.overview) ? body.overview : []);
      setTopProducts(Array.isArray(body.topProducts) ? body.topProducts : []);
      setRangeLabel(dateFrom || dateTo ? `${dateFrom || 'البداية'} — ${dateTo || 'اليوم'}` : 'آخر 30 يومًا');
    } catch (caught) {
      const code = caught instanceof Error ? caught.message : 'REPORT_READ_FAILED';
      setError(code === 'INVALID_DATE_RANGE' ? 'تاريخ البداية يجب أن يسبق تاريخ النهاية.' : 'تعذر تحميل التقرير للفترة المحددة.');
    } finally {
      setBusy(false);
    }
  }

  function resetFilters() {
    setDateFrom('');
    setDateTo('');
    setCurrency('');
    setOverview(initialOverview);
    setTopProducts(initialTopProducts);
    setRangeLabel('آخر 30 يومًا');
    setError(null);
  }

  const selectedOverview = currency ? overview[0] : null;

  return <div className="detail-stack reports-workspace">
    <div className="surface report-filter-surface">
      <div className="surface-head compact-head">
        <div><strong>نطاق التقرير</strong><p>غيّر الفترة أو اعزل عملة واحدة للحصول على قراءة مالية دقيقة.</p></div>
        <div className="report-scope"><span>{rangeLabel}</span><b>{currency || 'كل العملات'}</b></div>
      </div>
      <form className="report-filters" onSubmit={applyFilters}>
        <label><span>من</span><input type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} /></label>
        <label><span>إلى</span><input type="date" value={dateTo} onChange={(event) => setDateTo(event.target.value)} /></label>
        <label><span>العملة</span><select value={currency} onChange={(event) => setCurrency(event.target.value as Currency)}><option value="">كل العملات</option><option value="YER">YER</option><option value="SAR">SAR</option><option value="USD">USD</option></select></label>
        <button className="primary-filter" type="submit" disabled={busy}>{busy ? 'جارٍ التحديث…' : 'تطبيق'}</button>
        <button className="filter-reset" type="button" disabled={busy} onClick={resetFilters}>إعادة ضبط</button>
      </form>
      {error && <div className="contract-alert">{error}</div>}
    </div>

    {currency ? <>
      <div className="balance-grid report-kpis">
        <div className="balance-card"><span>المبيعات</span><b>{formatNumber(totals.sales)}</b><small>{currency}</small></div>
        <div className="balance-card"><span>الربح التقديري</span><b>{formatNumber(totals.profit)}</b><small>{currency}</small></div>
        <div className="balance-card"><span>التحصيل</span><b>{formatNumber(totals.collected)}</b><small>{currency}</small></div>
        <div className="balance-card"><span>المتبقي</span><b>{formatNumber(totals.remaining)}</b><small>{currency}</small></div>
      </div>
      {selectedOverview && <div className="surface currency-operations-summary">
        <div className="surface-head compact-head"><div><strong>نشاط {currency}</strong><p>قراءة تشغيلية للفترة المحددة دون أي تحويل بين العملات.</p></div></div>
        <div className="metric-pairs wide-pairs">
          <div><span>عدد المبيعات</span><b>{formatNumber(selectedOverview.sales_count)}</b></div>
          <div><span>مبيعات آجلة</span><b>{formatNumber(selectedOverview.credit_sales_total)} {currency}</b></div>
          <div><span>عمليات نشطة</span><b>{formatNumber(selectedOverview.active_transactions_count)}</b></div>
          <div><span>عمليات ملغاة</span><b>{formatNumber(selectedOverview.cancelled_transactions_count)}</b></div>
        </div>
      </div>}
    </> : <div className="report-grid currency-report-grid">{overview.map((row) => <article className="metric-card currency-metric-card" key={String(row.currency)}>
      <div className="metric-title"><strong>{String(row.currency)}</strong><span>{rangeLabel}</span></div>
      <div className="metric-main">{formatNumber(row.sales_total)}</div>
      <small>إجمالي المبيعات · {String(row.currency)}</small>
      <div className="metric-pairs"><div><span>الربح التقديري</span><b>{formatNumber(row.estimated_profit_total)}</b></div><div><span>المتبقي</span><b>{formatNumber(row.remaining_total)}</b></div><div><span>التحصيل</span><b>{formatNumber(row.collected_total)}</b></div><div><span>عدد المبيعات</span><b>{formatNumber(row.sales_count)}</b></div></div>
    </article>)}</div>}

    <div className="surface top-products-surface">
      <div className="surface-head compact-head"><div><strong>الأصناف الأعلى مبيعًا</strong><p>{currency ? `الترتيب حسب قيمة المبيعات بعملة ${currency}.` : 'كل صف يحتفظ بعملته الأصلية؛ لا توجد مجاميع مختلطة.'}</p></div><span className="count-pill">{topProducts.length} صنف</span></div>
      <div className="data-list top-products-list">{topProducts.length === 0 ? <div className="empty-state"><strong>لا توجد مبيعات مطابقة للفلاتر.</strong><p>جرّب توسيع الفترة أو تغيير العملة.</p></div> : topProducts.map((row, index) => <div className="data-row static product-rank-row" key={`${row.product_name}-${row.currency}`}><span className="rank-number">{index + 1}</span><div className="product-rank-name"><b>{String(row.product_name)}</b><small>{formatNumber(row.total_quantity)} وحدة · {formatNumber(row.invoices_count)} فاتورة</small></div><div className="row-meta"><b>{formatNumber(row.total_sales)} {String(row.currency)}</b><small>ربح {formatNumber(row.total_estimated_profit)}</small></div></div>)}</div>
    </div>
  </div>;
}
