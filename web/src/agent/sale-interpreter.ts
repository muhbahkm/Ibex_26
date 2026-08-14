import OpenAI from 'openai';

export type SaleIntent = {
  product_query: string;
  unit_query: string | null;
  customer_query: string | null;
  quantity: number;
  unit_price: number | null;
  currency: 'YER' | 'SAR' | 'USD' | 'AUTO';
  payment_status: 'cash' | 'credit' | 'partial';
  paid_amount: number | null;
  notes: string | null;
};

const schema = {
  type: 'object',
  additionalProperties: false,
  required: ['product_query', 'unit_query', 'customer_query', 'quantity', 'unit_price', 'currency', 'payment_status', 'paid_amount', 'notes'],
  properties: {
    product_query: { type: 'string' },
    unit_query: { type: ['string', 'null'] },
    customer_query: { type: ['string', 'null'] },
    quantity: { type: 'number', exclusiveMinimum: 0 },
    unit_price: { type: ['number', 'null'], minimum: 0 },
    currency: { type: 'string', enum: ['YER', 'SAR', 'USD', 'AUTO'] },
    payment_status: { type: 'string', enum: ['cash', 'credit', 'partial'] },
    paid_amount: { type: ['number', 'null'], minimum: 0 },
    notes: { type: ['string', 'null'] },
  },
} as const;

function getClient() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('AI_NOT_CONFIGURED');

  return new OpenAI({
    apiKey,
    baseURL: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  });
}

export async function interpretSaleCommand(message: string): Promise<SaleIntent> {
  const client = getClient();

  const completion = await client.chat.completions.create({
    model: process.env.GEMINI_MODEL ?? 'gemini-2.5-flash-lite',
    messages: [
      {
        role: 'system',
        content: [
          'أنت محلل أوامر مبيعات لمتجر عسل يمني.',
          'استخرج فقط ما قاله المستخدم ولا تخترع أسماء عملاء أو أصناف أو أسعار.',
          'YER = ريال يمني، SAR = ريال سعودي، USD = دولار.',
          'إذا لم يذكر العملة استخدم AUTO.',
          'إذا لم يذكر العميل أو قال زبون عام فاجعل customer_query = null.',
          'إذا لم يذكر السعر فاجعل unit_price = null.',
          'إذا كانت العملية نقدية فpayment_status=cash، وإذا آجل فcredit، وإذا دفع جزءًا فpartial.',
          'لا تنشئ أي معرفات قاعدة بيانات.',
        ].join('\n'),
      },
      { role: 'user', content: message },
    ],
    response_format: {
      type: 'json_schema',
      json_schema: {
        name: 'ibex_sale_intent',
        strict: true,
        schema,
      },
    },
  });

  const raw = completion.choices[0]?.message?.content;
  if (!raw) throw new Error('AI_EMPTY_RESPONSE');
  return JSON.parse(raw) as SaleIntent;
}
