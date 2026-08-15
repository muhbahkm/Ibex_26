import { sql } from '@/lib/db/neon';

export type AppUser = {
  id: string;
  business_id: string;
  full_name: string;
  phone: string | null;
  email: string | null;
  role: string;
  is_active: boolean;
};

export async function getCurrentAppUser(identity: string): Promise<AppUser | null> {
  const rows = await sql`
    with _identity as materialized (
      select
        set_config('app.current_user_id', ${identity}, true),
        set_config('app.auth_provider', 'neon_auth', true)
    )
    select u.*
    from _identity
    cross join lateral public.ibex_had_get_current_app_user() u
    limit 1
  `;

  return (rows[0] as AppUser | undefined) ?? null;
}

export async function withIdentityCall<T>(identity: string, payload: unknown): Promise<T> {
  const json = JSON.stringify(payload);
  const rows = await sql`
    with _identity as materialized (
      select
        set_config('app.current_user_id', ${identity}, true),
        set_config('app.auth_provider', 'neon_auth', true)
    )
    select public.ibex_had_create_transaction_v2(${json}::jsonb) as result
    from _identity
  `;

  return rows[0]?.result as T;
}
