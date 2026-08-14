import { sql } from '@/lib/db/neon';

type ProductRow = {
  id: string;
  product_name: string;
  category: string | null;
  default_unit_id: string | null;
  default_unit_name: string | null;
  default_sale_price: number;
  default_cost: number;
  default_currency: 'YER' | 'SAR' | 'USD';
};

type CustomerRow = {
  id: string;
  display_name: string;
  phone: string | null;
  is_general_customer: boolean;
};

type UnitRow = { id: string; unit_name: string; unit_code: string | null };
type CashRow = { cash_account_id: string; currency: 'YER' | 'SAR' | 'USD'; is_active: boolean };

function provider() {
  return 'neon_auth';
}

export async function searchProducts(identity: string, businessId: string, query: string) {
  return (await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', ${provider()}, true)
    )
    select p.* from _identity
    cross join lateral public.ibex_had_search_products(${businessId}::uuid, ${query}, 5) p
  `) as ProductRow[];
}

export async function searchCustomers(identity: string, businessId: string, query: string) {
  return (await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', ${provider()}, true)
    )
    select c.* from _identity
    cross join lateral public.ibex_had_search_customers(${businessId}::uuid, ${query}, 5) c
  `) as CustomerRow[];
}

export async function searchUnits(identity: string, businessId: string, query: string) {
  return (await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', ${provider()}, true)
    )
    select u.* from _identity
    cross join lateral public.ibex_had_search_units(${businessId}::uuid, ${query}, 5) u
  `) as UnitRow[];
}

export async function getGeneralCustomer(identity: string, businessId: string) {
  const rows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', ${provider()}, true)
    )
    select public.ibex_had_get_general_customer(${businessId}::uuid) as id from _identity
  `;
  return rows[0]?.id as string | null;
}

export async function getCashAccount(identity: string, businessId: string, currency: 'YER' | 'SAR' | 'USD') {
  const rows = (await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', ${provider()}, true)
    )
    select c.* from _identity
    cross join lateral public.ibex_had_get_cash_summary(${businessId}::uuid) c
    where c.currency = ${currency}::public.ibex_had_currency and c.is_active = true
    limit 1
  `) as CashRow[];
  return rows[0] ?? null;
}
