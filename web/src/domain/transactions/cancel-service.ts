import { z } from 'zod';
import { getCurrentAppUser } from '@/lib/db/identity';
import { sql } from '@/lib/db/neon';

const cancelSchema = z.object({
  transaction_id: z.string().uuid(),
  reason: z.string().trim().min(4).max(300),
});

type CancelResult = {
  success: boolean;
  transaction_id: string;
  transaction_no: string;
  status: 'cancelled';
  cash_reversed: boolean;
};

export async function cancelTransaction(authIdentity: string, rawInput: unknown): Promise<CancelResult> {
  const appUser = await getCurrentAppUser(authIdentity);
  if (!appUser) throw new Error('ACCOUNT_NOT_LINKED');

  const input = cancelSchema.parse(rawInput);

  const detailRows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${authIdentity}, true), set_config('app.auth_provider', 'neon_auth', true)
    )
    select public.ibex_had_get_transaction_detail(${input.transaction_id}::uuid) as detail
    from _identity
  `;

  const detail = detailRows[0]?.detail as { transaction?: { business_id?: string; transaction_status?: string } } | undefined;
  if (!detail?.transaction) throw new Error('TRANSACTION_NOT_FOUND');
  if (detail.transaction.business_id !== appUser.business_id) throw new Error('TRANSACTION_OUT_OF_SCOPE');
  if (detail.transaction.transaction_status === 'cancelled') throw new Error('TRANSACTION_ALREADY_CANCELLED');

  const resultRows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${authIdentity}, true), set_config('app.auth_provider', 'neon_auth', true)
    )
    select public.ibex_had_cancel_transaction(
      ${input.transaction_id}::uuid,
      ${input.reason}::text,
      ${appUser.id}::uuid
    ) as result
    from _identity
  `;

  return resultRows[0]?.result as CancelResult;
}
