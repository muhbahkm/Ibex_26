import assert from 'node:assert/strict';

const {
  businessOverviewRowsSchema,
  recentTransactionsSchema,
  topProductsSchema,
} = await import('../src/lib/contracts/workspace.ts');

const transaction = recentTransactionsSchema.parse([{
  id: '6d03b044-b524-47da-b0ec-30d7b649805c',
  transaction_no: 'IBX-20260815-0005',
  transaction_type: 'payment_voucher',
  transaction_status: 'active',
  transaction_datetime: '2026-08-15T10:05:00.000Z',
  currency: 'YER',
  customer_name: 'سحب شخصي للمالك',
  customer_phone: null,
  payment_status: 'cash',
  total_amount: '15000.00',
  paid_amount: '15000.00',
  remaining_amount: '0.00',
  estimated_profit: '0.00',
  cash_account_name: 'الصندوق - YER',
  notes: null,
}])[0];

assert.equal(transaction.id, '6d03b044-b524-47da-b0ec-30d7b649805c');
assert.equal(transaction.total_amount, 15000);
assert.equal(transaction.currency, 'YER');

const missingId = recentTransactionsSchema.safeParse([{
  transaction_no: 'BROKEN-ROW',
  transaction_type: 'sales_invoice',
  transaction_status: 'active',
  transaction_datetime: '2026-08-15T10:05:00.000Z',
  currency: 'YER',
  customer_name: null,
  customer_phone: null,
  payment_status: 'cash',
  total_amount: 1,
  paid_amount: 1,
  remaining_amount: 0,
  estimated_profit: 0,
  cash_account_name: null,
  notes: null,
}]);
assert.equal(missingId.success, false, 'transactions without an id must be rejected before reaching React');

const overview = businessOverviewRowsSchema.parse([{
  currency: 'SAR',
  sales_count: '2',
  sales_total: '1027.50',
  purchases_count: '0',
  purchases_total: '0',
  receipts_total: '20',
  payments_total: '0',
  credit_sales_total: '652.50',
  collected_total: '395',
  remaining_total: '652.50',
  estimated_profit_total: '296.14',
  active_transactions_count: '3',
  cancelled_transactions_count: '0',
}])[0];
assert.equal(overview.sales_total, 1027.5);
assert.equal(overview.sales_count, 2);

const product = topProductsSchema.parse([{
  product_name: 'سدر',
  currency: 'YER',
  invoices_count: '3',
  total_quantity: '2.5',
  total_sales: '65000',
  total_estimated_profit: '5550',
  last_sold_at: '2026-08-15T09:49:17.925Z',
}])[0];
assert.equal(product.total_quantity, 2.5);

console.log('Workspace runtime contract tests passed.');
