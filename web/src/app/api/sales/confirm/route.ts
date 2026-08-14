import { auth } from '@/lib/auth/server';
import { confirmSale } from '@/domain/sales/service';

export async function POST(request: Request) {
  const { data: session } = await auth.getSession();
  if (!session?.user) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  try {
    const result = await confirmSale(session.user.id, await request.json());
    return Response.json({ transaction: result }, { status: 201 });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'UNKNOWN_ERROR';
    const status = code === 'ACCOUNT_NOT_LINKED' || code === 'BUSINESS_SCOPE_MISMATCH' ? 403 : 400;
    return Response.json({ error: code }, { status });
  }
}
