import { auth } from '@/lib/auth/server';
import { getCurrentAppUser } from '@/lib/db/identity';
import { getBusinessOverview, getCustomerBalances, getCustomerDetail, getOverdueCustomers, getRecentTransactions, getTopProducts, getTransactionDetail } from '@/lib/db/workspace';

const allowedDebtDays = new Set([7, 14, 30, 60, 90]);

export async function GET(request: Request) {
  const { data: session } = await auth.getSession();
  if (!session?.user) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });
  const appUser = await getCurrentAppUser(session.user.id);
  if (!appUser) return Response.json({ error: 'ACCOUNT_NOT_LINKED' }, { status: 403 });

  const url = new URL(request.url);
  const section = url.searchParams.get('section') ?? 'overview';
  const detail = url.searchParams.get('detail');
  const recordId = url.searchParams.get('id');
  const requestedDebtDays = Number(url.searchParams.get('days') ?? 30);
  const debtDays = allowedDebtDays.has(requestedDebtDays) ? requestedDebtDays : 30;
  const context = { identity: session.user.id, businessId: appUser.business_id };

  try {
    if (detail === 'customer' && recordId) {
      const value = await getCustomerDetail(context, recordId);
      return value ? Response.json({ detail, value }) : Response.json({ error: 'CUSTOMER_NOT_FOUND' }, { status: 404 });
    }
    if (detail === 'transaction' && recordId) {
      const value = await getTransactionDetail(context, recordId);
      return value ? Response.json({ detail, value }) : Response.json({ error: 'TRANSACTION_NOT_FOUND' }, { status: 404 });
    }
    if (section === 'customers') return Response.json({ section, rows: await getCustomerBalances(context, false) });
    if (section === 'transactions') return Response.json({ section, rows: await getRecentTransactions(context, 120) });
    if (section === 'debts') return Response.json({ section, rows: await getOverdueCustomers(context, debtDays), days: debtDays });
    if (section === 'reports') {
      const [rows, topProducts] = await Promise.all([getBusinessOverview(context, 30), getTopProducts(context, 30)]);
      return Response.json({ section, rows, topProducts });
    }
    const [transactions, debts, overview] = await Promise.all([getRecentTransactions(context, 8), getOverdueCustomers(context, 30), getBusinessOverview(context, 30)]);
    return Response.json({ section: 'overview', transactions, debts, overview });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'WORKSPACE_READ_FAILED';
    return Response.json({ error: code }, { status: 400 });
  }
}
