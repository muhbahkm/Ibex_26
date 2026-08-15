import { auth } from '@/lib/auth/server';
import { getCurrentAppUser } from '@/lib/db/identity';
import { getCashAccount, getCustomerById, searchCustomers, searchProducts, searchUnits } from '@/lib/db/lookups';

const currencies = new Set(['YER', 'SAR', 'USD']);

export async function GET(request: Request) {
  const { data: session } = await auth.getSession();
  if (!session?.user) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  const appUser = await getCurrentAppUser(session.user.id);
  if (!appUser) return Response.json({ error: 'ACCOUNT_NOT_LINKED' }, { status: 403 });

  const url = new URL(request.url);
  const kind = url.searchParams.get('kind');
  const query = url.searchParams.get('q')?.trim() ?? '';

  try {
    if (kind === 'products') {
      return Response.json({ rows: await searchProducts(session.user.id, appUser.business_id, query) });
    }
    if (kind === 'customers') {
      return Response.json({ rows: await searchCustomers(session.user.id, appUser.business_id, query) });
    }
    if (kind === 'customer') {
      const id = url.searchParams.get('id')?.trim() ?? '';
      if (!id) return Response.json({ error: 'CUSTOMER_ID_REQUIRED' }, { status: 400 });
      const row = await getCustomerById(session.user.id, appUser.business_id, id);
      if (!row) return Response.json({ error: 'CUSTOMER_NOT_FOUND' }, { status: 404 });
      return Response.json({ row });
    }
    if (kind === 'units') {
      return Response.json({ rows: await searchUnits(session.user.id, appUser.business_id, query) });
    }
    if (kind === 'cash') {
      const currency = url.searchParams.get('currency') ?? '';
      if (!currencies.has(currency)) return Response.json({ error: 'INVALID_CURRENCY' }, { status: 400 });
      return Response.json({ row: await getCashAccount(session.user.id, appUser.business_id, currency as 'YER' | 'SAR' | 'USD') });
    }
    return Response.json({ error: 'INVALID_LOOKUP_KIND' }, { status: 400 });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'SALE_LOOKUP_FAILED';
    return Response.json({ error: code }, { status: 400 });
  }
}
