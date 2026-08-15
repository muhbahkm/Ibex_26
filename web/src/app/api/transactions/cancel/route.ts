import { auth } from '@/lib/auth/server';
import { cancelTransaction } from '@/domain/transactions/cancel-service';

export async function POST(request: Request) {
  const { data: session } = await auth.getSession();
  if (!session?.user) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  try {
    const result = await cancelTransaction(session.user.id, await request.json());
    return Response.json({ result });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'TRANSACTION_CANCEL_FAILED';
    const status = code === 'ACCOUNT_NOT_LINKED'
      ? 403
      : code.includes('OUT_OF_SCOPE')
        ? 403
        : code.includes('NOT_FOUND')
          ? 404
          : code.includes('ALREADY_CANCELLED')
            ? 409
            : 400;
    return Response.json({ error: code }, { status });
  }
}
