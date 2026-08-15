import { auth } from '@/lib/auth/server';
import { getCurrentAppUser } from '@/lib/db/identity';
import { getBusinessOverviewByRange, getTopProductsByRange } from '@/lib/db/workspace';

const currencies = new Set(['YER', 'SAR', 'USD']);
const datePattern = /^\d{4}-\d{2}-\d{2}$/;

export async function GET(request: Request) {
  const { data: session } = await auth.getSession();
  if (!session?.user) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  const appUser = await getCurrentAppUser(session.user.id);
  if (!appUser) return Response.json({ error: 'ACCOUNT_NOT_LINKED' }, { status: 403 });

  const url = new URL(request.url);
  const dateFrom = url.searchParams.get('dateFrom') || undefined;
  const dateTo = url.searchParams.get('dateTo') || undefined;
  const currencyParam = url.searchParams.get('currency') || undefined;

  if (dateFrom && !datePattern.test(dateFrom)) return Response.json({ error: 'INVALID_DATE_FROM' }, { status: 400 });
  if (dateTo && !datePattern.test(dateTo)) return Response.json({ error: 'INVALID_DATE_TO' }, { status: 400 });
  if (dateFrom && dateTo && dateFrom > dateTo) return Response.json({ error: 'INVALID_DATE_RANGE' }, { status: 400 });
  if (currencyParam && !currencies.has(currencyParam)) return Response.json({ error: 'INVALID_CURRENCY' }, { status: 400 });

  const context = { identity: session.user.id, businessId: appUser.business_id };
  const currency = currencyParam as 'YER' | 'SAR' | 'USD' | undefined;

  try {
    const [overview, topProducts] = await Promise.all([
      getBusinessOverviewByRange(context, dateFrom, dateTo),
      getTopProductsByRange(context, dateFrom, dateTo, currency),
    ]);

    return Response.json({
      overview: currency ? overview.filter((row) => row.currency === currency) : overview,
      topProducts,
      filters: { dateFrom: dateFrom ?? null, dateTo: dateTo ?? null, currency: currency ?? null },
    });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'REPORT_READ_FAILED';
    return Response.json({ error: code }, { status: 400 });
  }
}
