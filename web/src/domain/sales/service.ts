import { getCurrentAppUser, withIdentityCall } from '@/lib/db/identity';
import { getCustomerById, getProductById, getUnitById } from '@/lib/db/lookups';
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

async function assertBusinessScopedReferences(authIdentity: string, businessId: string, draft: SaleDraft) {
  if (draft.customer_id) {
    const customer = await getCustomerById(authIdentity, businessId, draft.customer_id);
    if (!customer) throw new Error('CUSTOMER_SCOPE_MISMATCH');
  }

  for (const item of draft.items) {
    if (item.product_id) {
      const product = await getProductById(authIdentity, businessId, item.product_id);
      if (!product) throw new Error('PRODUCT_SCOPE_MISMATCH');
    }
    if (item.unit_id) {
      const unit = await getUnitById(authIdentity, businessId, item.unit_id);
      if (!unit) throw new Error('UNIT_SCOPE_MISMATCH');
    }
  }
}

export async function confirmSale(authIdentity: string, rawDraft: unknown): Promise<ConfirmedSale> {
  const appUser = await getCurrentAppUser(authIdentity);
  if (!appUser) throw new Error('ACCOUNT_NOT_LINKED');

  const draft: SaleDraft = saleDraftSchema.parse(rawDraft);
  if (draft.business_id !== appUser.business_id) throw new Error('BUSINESS_SCOPE_MISMATCH');
  await assertBusinessScopedReferences(authIdentity, appUser.business_id, draft);

  return withIdentityCall<ConfirmedSale>(authIdentity, {
    ...draft,
    transaction_type: 'sales_invoice',
    created_by: appUser.id,
    send_whatsapp: false,
    auto_create_products: true,
  });
}
