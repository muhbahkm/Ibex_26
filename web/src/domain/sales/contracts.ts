import { z } from 'zod';

export const saleItemSchema = z.object({
  product_id: z.string().uuid().optional(),
  product_name: z.string().trim().min(1),
  unit_id: z.string().uuid().optional(),
  unit_name: z.string().trim().min(1),
  quantity: z.number().positive(),
  unit_price: z.number().nonnegative(),
  estimated_unit_cost: z.number().nonnegative().optional(),
  category: z.string().trim().optional(),
  notes: z.string().trim().optional(),
});

export const saleDraftSchema = z.object({
  business_id: z.string().uuid(),
  customer_id: z.string().uuid().optional(),
  party_name: z.string().trim().optional(),
  party_phone: z.string().trim().optional(),
  currency: z.enum(['YER', 'SAR', 'USD']),
  payment_status: z.enum(['cash', 'credit', 'partial']),
  paid_amount: z.number().nonnegative().default(0),
  discount_amount: z.number().nonnegative().default(0),
  cash_account_id: z.string().uuid().optional(),
  notes: z.string().trim().optional(),
  items: z.array(saleItemSchema).min(1),
});

export type SaleDraft = z.infer<typeof saleDraftSchema>;
