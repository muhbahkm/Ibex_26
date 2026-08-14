import { getCurrentAppUser, withIdentityCall } from '@/lib/db/identity';
import { saleDraftSchema, type SaleDraft } from './contracts';

export type ConfirmedSale = {
  success: boolean;
  transaction_id: string;
  transaction_no: string;
  currency: 'YER' | 'SAR' | 'USD';
  total_amount: number;
  paid_amount: number;
  remaining_amount: number;
  estimated_profit: number;
};

export async function confirmSale(authIdentity: string, rawDraft: unknown): Promise<ConfirmedSale> {
  const appUser = await getCurrentAppUser(authIdentity);
  if (!appUser) throw new Error('ACCOUNT_NOT_LINKED');

  const draft: SaleDraft = saleDraftSchema.parse(rawDraft);
  if (draft.business_id !== appUser.business_id) throw new Error('BUSINESS_SCOPE_MISMATCH');

  return withIdentityCall<ConfirmedSale>(authIdentity, {
    ...draft,
    transaction_type: 'sales_invoice',
    created_by: appUser.id,
    send_whatsapp: false,
    auto_create_products: true,
  });
}
