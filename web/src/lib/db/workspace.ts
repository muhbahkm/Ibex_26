import { sql } from '@/lib/db/neon';

type IdentityArgs = { identity: string; businessId: string };

type Currency = 'YER' | 'SAR' | 'USD';

export type RecentTransaction = {
  id: string; transaction_no: string; transaction_type: string; transaction_status: string;
  transaction_datetime: string; currency: Currency; customer_name: string | null;
  customer_phone: string | null; payment_status: string; total_amount: number; paid_amount: number;
  remaining_amount: number; estimated_profit: number; cash_account_name: string | null; notes: string | null;
};

export type CustomerBalance = { customer_id: string; display_name: string; phone: string | null; currency: Currency; balance: number; last_transaction_at: string | null };
export type OverdueCustomer = CustomerBalance & { last_ledger_activity_at: string | null; days_since_last_activity: number | null };
export type BusinessOverview = { currency: Currency; sales_count: number; sales_total: number; purchases_count: number; purchases_total: number; receipts_total: number; payments_total: number; credit_sales_total: number; collected_total: number; remaining_total: number; estimated_profit_total: number; active_transactions_count: number; cancelled_transactions_count: number };

function numberize<T extends Record<string, unknown>>(row: T, keys: string[]) {
  const result = { ...row } as Record<string, unknown>;
  for (const key of keys) if (result[key] !== null && result[key] !== undefined) result[key] = Number(result[key]);
  return result as T;
}

function identityCte(identity: string) { return identity; }

export async function getRecentTransactions({ identity, businessId }: IdentityArgs, limit = 30) {
  const rows = await sql`with _identity as materialized (select set_config('app.current_user_id', ${identityCte(identity)}, true), set_config('app.auth_provider', 'neon_auth', true)) select t.* from _identity cross join lateral public.ibex_had_get_recent_transactions(${businessId}::uuid, ${limit}) t`;
  return rows.map((row) => numberize(row as RecentTransaction, ['total_amount', 'paid_amount', 'remaining_amount', 'estimated_profit']));
}

export async function getCustomerBalances({ identity, businessId }: IdentityArgs, onlyPositive = false) {
  const rows = await sql`with _identity as materialized (select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)) select c.* from _identity cross join lateral public.ibex_had_get_customer_balances_report(${businessId}::uuid, ${onlyPositive}) c`;
  return rows.map((row) => numberize(row as CustomerBalance, ['balance']));
}

export async function getOverdueCustomers({ identity, businessId }: IdentityArgs, days = 30) {
  const rows = await sql`with _identity as materialized (select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)) select c.* from _identity cross join lateral public.ibex_had_get_overdue_customers(${businessId}::uuid, ${days}) c`;
  return rows.map((row) => numberize(row as OverdueCustomer, ['balance', 'days_since_last_activity']));
}

export async function getBusinessOverview({ identity, businessId }: IdentityArgs, days = 30) {
  const rows = await sql`with _identity as materialized (select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)) select o.* from _identity cross join lateral public.ibex_had_get_business_overview(${businessId}::uuid, current_date - ${days}::integer, current_date) o`;
  const numericKeys = ['sales_count','sales_total','purchases_count','purchases_total','receipts_total','payments_total','credit_sales_total','collected_total','remaining_total','estimated_profit_total','active_transactions_count','cancelled_transactions_count'];
  return rows.map((row) => numberize(row as BusinessOverview, numericKeys));
}

export async function getTopProducts({ identity, businessId }: IdentityArgs, days = 30) {
  const rows = await sql`with _identity as materialized (select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)) select p.* from _identity cross join lateral public.ibex_had_get_top_products(${businessId}::uuid, current_date - ${days}::integer, current_date, null, 8) p`;
  return rows.map((row) => numberize(row as Record<string, unknown>, ['invoices_count','total_quantity','total_sales','total_estimated_profit']));
}

export async function getBusinessOverviewByRange({ identity, businessId }: IdentityArgs, dateFrom?: string, dateTo?: string) {
  const rows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)
    )
    select o.*
    from _identity
    cross join lateral public.ibex_had_get_business_overview(
      ${businessId}::uuid,
      coalesce(${dateFrom ?? null}::date, current_date - 30),
      coalesce(${dateTo ?? null}::date, current_date)
    ) o
  `;
  const numericKeys = ['sales_count','sales_total','purchases_count','purchases_total','receipts_total','payments_total','credit_sales_total','collected_total','remaining_total','estimated_profit_total','active_transactions_count','cancelled_transactions_count'];
  return rows.map((row) => numberize(row as BusinessOverview, numericKeys));
}

export async function getTopProductsByRange({ identity, businessId }: IdentityArgs, dateFrom?: string, dateTo?: string, currency?: Currency) {
  const rows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)
    )
    select p.*
    from _identity
    cross join lateral public.ibex_had_get_top_products(
      ${businessId}::uuid,
      coalesce(${dateFrom ?? null}::date, current_date - 30),
      coalesce(${dateTo ?? null}::date, current_date),
      ${currency ?? null}::public.ibex_had_currency,
      12
    ) p
  `;
  return rows.map((row) => numberize(row as Record<string, unknown>, ['invoices_count','total_quantity','total_sales','total_estimated_profit']));
}

export async function getTransactionDetail({ identity, businessId }: IdentityArgs, transactionId: string) {
  const rows = await sql`with _identity as materialized (select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)) select public.ibex_had_get_transaction_detail(${transactionId}::uuid) as detail from _identity where exists (select 1 from public.ibex_had_transactions t where t.id=${transactionId}::uuid and t.business_id=${businessId}::uuid)`;
  return rows[0]?.detail ?? null;
}

export async function getCustomerDetail({ identity, businessId }: IdentityArgs, customerId: string) {
  const [profileRows, balances, ledgerRows] = await Promise.all([
    sql`with _identity as materialized (select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)) select c.* from _identity, public.ibex_had_customer_activity_view c where c.customer_id=${customerId}::uuid and c.business_id=${businessId}::uuid limit 1`,
    getCustomerBalances({ identity, businessId }, false),
    sql`with _identity as materialized (select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)) select s.* from _identity cross join lateral public.ibex_had_get_customer_statement_detailed(${businessId}::uuid, ${customerId}::uuid, null, null, null) s order by s.entry_datetime desc limit 40`,
  ]);
  const customer = profileRows[0] ? numberize(profileRows[0] as Record<string, unknown>, ['transactions_count','total_sales_amount','total_remaining_amount']) : null;
  if (!customer) return null;
  return {
    customer,
    balances: balances.filter((row) => row.customer_id === customerId),
    ledger: ledgerRows.map((row) => numberize(row as Record<string, unknown>, ['debit_amount','credit_amount','balance_after'])),
  };
}

export async function getCustomerStatement(
  { identity, businessId }: IdentityArgs,
  customerId: string,
  currency?: Currency,
  dateFrom?: string,
  dateTo?: string,
) {
  const rows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)
    )
    select s.*
    from _identity
    cross join lateral public.ibex_had_get_customer_statement_detailed(
      ${businessId}::uuid,
      ${customerId}::uuid,
      ${currency ?? null}::public.ibex_had_currency,
      ${dateFrom ?? null}::date,
      ${dateTo ?? null}::date
    ) s
    order by s.entry_datetime asc
  `;
  return rows.map((row) => numberize(row as Record<string, unknown>, ['debit_amount','credit_amount','balance_after']));
}
