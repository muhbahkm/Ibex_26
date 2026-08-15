import { z } from 'zod';

export const currencySchema = z.enum(['YER', 'SAR', 'USD']);
const moneySchema = z.coerce.number().finite();
const countSchema = z.coerce.number().finite();
const nullableTimestampSchema = z.string().min(1).nullable();

export const recentTransactionSchema = z.object({
  id: z.string().uuid(),
  transaction_no: z.string().min(1),
  transaction_type: z.string().min(1),
  transaction_status: z.string().min(1),
  transaction_datetime: z.string().min(1),
  currency: currencySchema,
  customer_name: z.string().nullable(),
  customer_phone: z.string().nullable(),
  payment_status: z.string().min(1),
  total_amount: moneySchema,
  paid_amount: moneySchema,
  remaining_amount: moneySchema,
  estimated_profit: moneySchema,
  cash_account_name: z.string().nullable(),
  notes: z.string().nullable(),
}).passthrough();

export const customerBalanceSchema = z.object({
  customer_id: z.string().uuid(),
  display_name: z.string().min(1),
  phone: z.string().nullable(),
  currency: currencySchema,
  balance: moneySchema,
  last_transaction_at: nullableTimestampSchema,
}).passthrough();

export const overdueCustomerSchema = z.object({
  customer_id: z.string().uuid(),
  display_name: z.string().min(1),
  phone: z.string().nullable(),
  currency: currencySchema,
  balance: moneySchema,
  last_ledger_activity_at: nullableTimestampSchema,
  days_since_last_activity: z.coerce.number().int().nonnegative().nullable(),
}).passthrough();

export const businessOverviewSchema = z.object({
  currency: currencySchema,
  sales_count: countSchema,
  sales_total: moneySchema,
  purchases_count: countSchema,
  purchases_total: moneySchema,
  receipts_total: moneySchema,
  payments_total: moneySchema,
  credit_sales_total: moneySchema,
  collected_total: moneySchema,
  remaining_total: moneySchema,
  estimated_profit_total: moneySchema,
  active_transactions_count: countSchema,
  cancelled_transactions_count: countSchema,
}).passthrough();

export const topProductSchema = z.object({
  product_name: z.string().min(1),
  currency: currencySchema,
  invoices_count: countSchema,
  total_quantity: moneySchema,
  total_sales: moneySchema,
  total_estimated_profit: moneySchema,
  last_sold_at: nullableTimestampSchema,
}).passthrough();

export const recentTransactionsSchema = z.array(recentTransactionSchema);
export const customerBalancesSchema = z.array(customerBalanceSchema);
export const overdueCustomersSchema = z.array(overdueCustomerSchema);
export const businessOverviewRowsSchema = z.array(businessOverviewSchema);
export const topProductsSchema = z.array(topProductSchema);

export type Currency = z.infer<typeof currencySchema>;
export type RecentTransaction = z.infer<typeof recentTransactionSchema>;
export type CustomerBalance = z.infer<typeof customerBalanceSchema>;
export type OverdueCustomer = z.infer<typeof overdueCustomerSchema>;
export type BusinessOverview = z.infer<typeof businessOverviewSchema>;
export type TopProduct = z.infer<typeof topProductSchema>;

export function parseWorkspaceRows<T>(schema: z.ZodType<T>, value: unknown, contractName: string): T {
  const parsed = schema.safeParse(value);
  if (parsed.success) return parsed.data;

  const first = parsed.error.issues[0];
  const path = first?.path.length ? first.path.join('.') : 'root';
  console.error('[workspace-contract]', contractName, parsed.error.flatten());
  throw new Error(`WORKSPACE_CONTRACT_INVALID:${contractName}:${path}`);
}
