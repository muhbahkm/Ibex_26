import { auth } from '@/lib/auth/server';
import { createCustomerReceipt } from '@/domain/receipts/service';

export async function POST(request: Request) {
  const { data: session } = await auth.getSession();
  if (!session?.user) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  try {
    const transaction = await createCustomerReceipt(session.user.id, await request.json());
    return Response.json({ transaction }, { status: 201 });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'RECEIPT_CREATE_FAILED';
    const status = code === 'ACCOUNT_NOT_LINKED' ? 403 : code.includes('BALANCE') ? 409 : 400;
    return Response.json({ error: code }, { status });
  }
}
