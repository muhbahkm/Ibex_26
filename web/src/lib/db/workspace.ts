import { sql } from '@/lib/db/neon';

type IdentityArgs = { identity: string; businessId: string };

export type RecentTransaction = {
  id: string;
  transaction_no: string;
  transaction_type: string;
  transaction_status: string;
  transaction_datetime: string;
  currency: 'YER' | 'SAR' | 'USD';
  customer_name: string | null;
  customer_phone: string | null;
  payment_status: string;
  total_amount: number;
  paid_amount: number;
  remaining_amount: number;
  estimated_profit: number;
  cash_account_name: string | null;
  notes: string | null;
};

export type CustomerBalance = {
  customer_id: string;
  display_name: string;
  phone: string | null;
  currency: 'YER' | 'SAR' | 'USD';
  balance: number;
  last_transaction_at: string | null;
};

export type OverdueCustomer = {
  customer_id: string;
  display_name: string;
  phone: string | null;
  currency: 'YER' | 'SAR' | 'USD';
  balance: number;
  last_ledger_activity_at: string | null;
  days_since_last_activity: number | null;
};

export type BusinessOverview = {
  currency: 'YER' | 'SAR' | 'USD';
  sales_count: number;
  sales_total: number;
  purchases_count: number;
  purchases_total: number;
  receipts_total: number;
  payments_total: number;
  credit_sales_total: number;
  collected_total: number;
  remaining_total: number;
  estimated_profit_total: number;
  active_transactions_count: number;
  cancelled_transactions_count: number;
};

function numberize<T extends Record<string, unknown>>(row: T, keys: string[]) {
  const result = { ...row } as Record<string, unknown>;
  for (const key of keys) {
    if (result[key] !== null && result[key] !== undefined) result[key] = Number(result[key]);
  }
  return result as T;
}

export async function getRecentTransactions({ identity, businessId }: IdentityArgs, limit = 30) {
  const rows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)
    )
    select t.* from _identity
    cross join lateral public.ibex_had_get_recent_transactions(${businessId}::uuid, ${limit}) t
  `;
  return rows.map((row) => numberize(row as RecentTransaction, ['total_amount', 'paid_amount', 'remaining_amount', 'estimated_profit']));
}

export async function getCustomerBalances({ identity, businessId }: IdentityArgs, onlyPositive = false) {
  const rows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)
    )
    select c.* from _identity
    cross join lateral public.ibex_had_get_customer_balances_report(${businessId}::uuid, ${onlyPositive}) c
  `;
  return rows.map((row) => numberize(row as CustomerBalance, ['balance']));
}

export async function getOverdueCustomers({ identity, businessId }: IdentityArgs, days = 30) {
  const rows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)
    )
    select c.* from _identity
    cross join lateral public.ibex_had_get_overdue_customers(${businessId}::uuid, ${days}) c
  `;
  return rows.map((row) => numberize(row as OverdueCustomer, ['balance', 'days_since_last_activity']));
}

export async function getBusinessOverview({ identity, businessId }: IdentityArgs, days = 30) {
  const rows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)
    )
    select o.* from _identity
    cross join lateral public.ibex_had_get_business_overview(${businessId}::uuid, current_date - ${days}::integer, current_date) o
  `;
  const numericKeys = ['sales_count', 'sales_total', 'purchases_count', 'purchases_total', 'receipts_total', 'payments_total', 'credit_sales_total', 'collected_total', 'remaining_total', 'estimated_profit_total', 'active_transactions_count', 'cancelled_transactions_count'];
  return rows.map((row) => numberize(row as BusinessOverview, numericKeys));
}
