import { z } from 'zod';
import { getCurrentAppUser, withIdentityCall } from '@/lib/db/identity';
import { getCashAccount } from '@/lib/db/lookups';
import { sql } from '@/lib/db/neon';

const receiptSchema = z.object({
  customer_id: z.string().uuid(),
  currency: z.enum(['YER', 'SAR', 'USD']),
  amount: z.number().positive(),
  notes: z.string().trim().max(500).optional(),
});

type ReceiptInput = z.infer<typeof receiptSchema>;

type ReceiptResult = {
  success: boolean;
  transaction_id: string;
  transaction_no: string;
  currency: ReceiptInput['currency'];
  total_amount: number;
  paid_amount: number;
  remaining_amount: number;
};

async function getCustomerBalance(identity: string, businessId: string, customerId: string, currency: ReceiptInput['currency']) {
  const rows = await sql`
    with _identity as materialized (
      select set_config('app.current_user_id', ${identity}, true), set_config('app.auth_provider', 'neon_auth', true)
    )
    select public.ibex_had_get_customer_balance(${businessId}::uuid, ${customerId}::uuid, ${currency}::public.ibex_had_currency) as balance
    from _identity
  `;
  return Number(rows[0]?.balance ?? 0);
}

export async function createCustomerReceipt(authIdentity: string, rawInput: unknown): Promise<ReceiptResult> {
  const appUser = await getCurrentAppUser(authIdentity);
  if (!appUser) throw new Error('ACCOUNT_NOT_LINKED');

  const input = receiptSchema.parse(rawInput);
  const currentBalance = await getCustomerBalance(authIdentity, appUser.business_id, input.customer_id, input.currency);
  if (currentBalance <= 0) throw new Error('CUSTOMER_HAS_NO_OUTSTANDING_BALANCE');
  if (input.amount > currentBalance) throw new Error('RECEIPT_EXCEEDS_CUSTOMER_BALANCE');

  const cash = await getCashAccount(authIdentity, appUser.business_id, input.currency);
  if (!cash) throw new Error('CASH_ACCOUNT_NOT_FOUND');

  return withIdentityCall<ReceiptResult>(authIdentity, {
    business_id: appUser.business_id,
    transaction_type: 'receipt_voucher',
    currency: input.currency,
    customer_id: input.customer_id,
    cash_account_id: cash.cash_account_id,
    total_amount: input.amount,
    paid_amount: input.amount,
    payment_status: 'cash',
    payment_method: 'cash',
    notes: input.notes,
    created_by: appUser.id,
    send_whatsapp: false,
    auto_create_products: false,
  });
}
