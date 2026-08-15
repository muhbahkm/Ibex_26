import { auth } from '@/lib/auth/server';
import { getCurrentAppUser } from '@/lib/db/identity';
import { getBusinessOverview, getCustomerBalances, getOverdueCustomers, getRecentTransactions } from '@/lib/db/workspace';

export async function GET(request: Request) {
  const { data: session } = await auth.getSession();
  if (!session?.user) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  const appUser = await getCurrentAppUser(session.user.id);
  if (!appUser) return Response.json({ error: 'ACCOUNT_NOT_LINKED' }, { status: 403 });

  const url = new URL(request.url);
  const section = url.searchParams.get('section') ?? 'overview';
  const context = { identity: session.user.id, businessId: appUser.business_id };

  try {
    if (section === 'customers') {
      return Response.json({ section, rows: await getCustomerBalances(context, false) });
    }
    if (section === 'transactions') {
      return Response.json({ section, rows: await getRecentTransactions(context, 40) });
    }
    if (section === 'debts') {
      return Response.json({ section, rows: await getOverdueCustomers(context, 30) });
    }
    if (section === 'reports') {
      return Response.json({ section, rows: await getBusinessOverview(context, 30) });
    }

    const [transactions, debts, overview] = await Promise.all([
      getRecentTransactions(context, 8),
      getOverdueCustomers(context, 30),
      getBusinessOverview(context, 30),
    ]);
    return Response.json({ section: 'overview', transactions, debts, overview });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'WORKSPACE_READ_FAILED';
    return Response.json({ error: code }, { status: 400 });
  }
}
