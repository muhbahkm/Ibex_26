import { auth } from '@/lib/auth/server';
import { getCurrentAppUser } from '@/lib/db/identity';
import { saleDraftSchema } from '@/domain/sales/contracts';

export async function POST(request: Request) {
  const { data: session } = await auth.getSession();
  if (!session?.user) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  const appUser = await getCurrentAppUser(session.user.id);
  if (!appUser) return Response.json({ error: 'ACCOUNT_NOT_LINKED' }, { status: 403 });

  const parsed = saleDraftSchema.safeParse(await request.json());
  if (!parsed.success) {
    return Response.json({ error: 'INVALID_DRAFT', details: parsed.error.flatten() }, { status: 400 });
  }

  if (parsed.data.business_id !== appUser.business_id) {
    return Response.json({ error: 'BUSINESS_SCOPE_MISMATCH' }, { status: 403 });
  }

  const total = parsed.data.items.reduce((sum, item) => sum + item.quantity * item.unit_price, 0) - parsed.data.discount_amount;
  const paid = parsed.data.paid_amount;

  return Response.json({
    draft: parsed.data,
    preview: {
      total_amount: Math.max(total, 0),
      paid_amount: paid,
      remaining_amount: Math.max(total - paid, 0),
      item_count: parsed.data.items.length,
    },
  });
}
