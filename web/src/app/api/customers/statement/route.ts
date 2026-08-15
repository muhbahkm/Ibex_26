import { auth } from '@/lib/auth/server';
import { getCurrentAppUser } from '@/lib/db/identity';
import { getCustomerStatement } from '@/lib/db/workspace';

const currencies = new Set(['YER', 'SAR', 'USD']);

export async function GET(request: Request) {
  const { data: session } = await auth.getSession();
  if (!session?.user) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  const appUser = await getCurrentAppUser(session.user.id);
  if (!appUser) return Response.json({ error: 'ACCOUNT_NOT_LINKED' }, { status: 403 });

  const url = new URL(request.url);
  const customerId = url.searchParams.get('customerId');
  const currencyParam = url.searchParams.get('currency');
  const dateFrom = url.searchParams.get('dateFrom') || undefined;
  const dateTo = url.searchParams.get('dateTo') || undefined;
  if (!customerId) return Response.json({ error: 'CUSTOMER_ID_REQUIRED' }, { status: 400 });
  if (currencyParam && !currencies.has(currencyParam)) return Response.json({ error: 'INVALID_CURRENCY' }, { status: 400 });

  try {
    const rows = await getCustomerStatement(
      { identity: session.user.id, businessId: appUser.business_id },
      customerId,
      currencyParam as 'YER' | 'SAR' | 'USD' | undefined,
      dateFrom,
      dateTo,
    );
    return Response.json({ rows });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'STATEMENT_READ_FAILED';
    return Response.json({ error: code }, { status: 400 });
  }
}
