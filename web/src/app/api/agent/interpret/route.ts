import { auth } from '@/lib/auth/server';
import { getCurrentAppUser } from '@/lib/db/identity';
import { getCashAccount, getGeneralCustomer, searchCustomers, searchProducts, searchUnits } from '@/lib/db/lookups';
import { interpretSaleCommand } from '@/agent/sale-interpreter';

function normalized(value: string) {
  return value
    .normalize('NFKC')
    .toLocaleLowerCase('en-US')
    .replace(/[\u064B-\u065F\u0670\u0640]/g, '')
    .replace(/[أإآ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/ة/g, 'ه')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function tokenScore(candidate: string, query: string) {
  const candidateNorm = normalized(candidate);
  const queryNorm = normalized(query);
  if (!candidateNorm || !queryNorm) return 0;
  if (candidateNorm === queryNorm) return 100;

  const candidateTokens = new Set(candidateNorm.split(' '));
  const queryTokens = new Set(queryNorm.split(' '));
  const intersection = [...queryTokens].filter((token) => candidateTokens.has(token)).length;
  const queryCoverage = intersection / queryTokens.size;
  const candidateCoverage = intersection / candidateTokens.size;

  let score = (queryCoverage * 55) + (candidateCoverage * 35);
  if (candidateNorm.startsWith(queryNorm) || queryNorm.startsWith(candidateNorm)) score += 8;
  if (candidateNorm.includes(queryNorm) || queryNorm.includes(candidateNorm)) score += 2;
  return Math.min(score, 99);
}

function resolveBestMatch<T>(rows: T[], label: (row: T) => string, query: string) {
  if (rows.length === 0) return null;

  const exact = rows.find((row) => normalized(label(row)) === normalized(query));
  if (exact) return exact;
  if (rows.length === 1) return rows[0];

  const ranked = rows
    .map((row) => ({ row, score: tokenScore(label(row), query) }))
    .sort((a, b) => b.score - a.score);

  const best = ranked[0];
  const second = ranked[1];
  if (!best || best.score < 78) return null;
  if (second && best.score - second.score < 12) return null;
  return best.row;
}

export async function POST(request: Request) {
  const { data: session } = await auth.getSession();
  if (!session?.user) return Response.json({ error: 'UNAUTHORIZED' }, { status: 401 });

  const body = (await request.json()) as { message?: string };
  const message = body.message?.trim();
  if (!message) return Response.json({ error: 'EMPTY_MESSAGE' }, { status: 400 });

  const appUser = await getCurrentAppUser(session.user.id);
  if (!appUser) return Response.json({ error: 'ACCOUNT_NOT_LINKED' }, { status: 403 });

  try {
    const intent = await interpretSaleCommand(message);

    const products = await searchProducts(session.user.id, appUser.business_id, intent.product_query);
    const product = resolveBestMatch(products, (row) => row.product_name, intent.product_query);
    if (!product) {
      return Response.json({
        status: 'needs_clarification',
        question: 'وجدت أكثر من صنف محتمل. أي صنف تقصد؟',
        candidates: products.map((row) => ({ id: row.id, label: row.product_name })),
      });
    }

    let unitId = product.default_unit_id;
    let unitName = product.default_unit_name;
    if (intent.unit_query) {
      const units = await searchUnits(session.user.id, appUser.business_id, intent.unit_query);
      const unit = resolveBestMatch(units, (row) => row.unit_name, intent.unit_query);
      if (!unit) {
        return Response.json({
          status: 'needs_clarification',
          question: 'الوحدة غير واضحة. أي وحدة تقصد؟',
          candidates: units.map((row) => ({ id: row.id, label: row.unit_name })),
        });
      }
      unitId = unit.id;
      unitName = unit.unit_name;
    }

    if (!unitId || !unitName) return Response.json({ error: 'PRODUCT_UNIT_NOT_CONFIGURED' }, { status: 409 });

    let customerId: string | null = null;
    let partyName: string | undefined;
    if (intent.customer_query) {
      const customers = await searchCustomers(session.user.id, appUser.business_id, intent.customer_query);
      const customer = resolveBestMatch(customers, (row) => row.display_name, intent.customer_query);
      if (!customer) {
        return Response.json({
          status: 'needs_clarification',
          question: 'وجدت أكثر من عميل محتمل. أي عميل تقصد؟',
          candidates: customers.map((row) => ({ id: row.id, label: row.display_name })),
        });
      }
      customerId = customer.id;
      partyName = customer.display_name;
    } else {
      customerId = await getGeneralCustomer(session.user.id, appUser.business_id);
      partyName = 'زبون عام';
    }

    if (!customerId) return Response.json({ error: 'CUSTOMER_NOT_RESOLVED' }, { status: 409 });

    const currency = intent.currency === 'AUTO' ? product.default_currency : intent.currency;
    const unitPrice = intent.unit_price ?? Number(product.default_sale_price);
    const subtotal = intent.quantity * unitPrice;
    const paidAmount = intent.payment_status === 'cash'
      ? subtotal
      : intent.payment_status === 'credit'
        ? 0
        : (intent.paid_amount ?? 0);

    if (intent.payment_status === 'partial' && paidAmount <= 0) {
      return Response.json({
        status: 'needs_clarification',
        question: 'ذكرت أن الدفع جزئي. كم المبلغ المدفوع الآن؟',
        candidates: [],
      });
    }

    const cash = paidAmount > 0 ? await getCashAccount(session.user.id, appUser.business_id, currency) : null;
    if (paidAmount > 0 && !cash) return Response.json({ error: 'CASH_ACCOUNT_NOT_FOUND' }, { status: 409 });

    const draft = {
      business_id: appUser.business_id,
      customer_id: customerId,
      party_name: partyName,
      currency,
      payment_status: intent.payment_status,
      paid_amount: paidAmount,
      discount_amount: 0,
      cash_account_id: cash?.cash_account_id,
      notes: intent.notes ?? undefined,
      items: [{
        product_id: product.id,
        product_name: product.product_name,
        unit_id: unitId,
        unit_name: unitName,
        quantity: intent.quantity,
        unit_price: unitPrice,
        category: product.category ?? undefined,
      }],
    };

    return Response.json({
      status: 'draft_ready',
      source_message: message,
      draft,
      preview: {
        customer_name: partyName,
        product_name: product.product_name,
        unit_name: unitName,
        quantity: intent.quantity,
        unit_price: unitPrice,
        currency,
        total_amount: subtotal,
        paid_amount: paidAmount,
        remaining_amount: Math.max(subtotal - paidAmount, 0),
      },
    });
  } catch (error) {
    const code = error instanceof Error ? error.message : 'UNKNOWN_ERROR';
    return Response.json({ error: code }, { status: code === 'AI_NOT_CONFIGURED' ? 503 : 400 });
  }
}
