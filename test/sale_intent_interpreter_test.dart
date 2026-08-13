import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/sale_intent_interpreter.dart';
import 'package:ibex_foundation_spike/core/errors/domain_error.dart';

void main() {
  const interpreter = SaleIntentInterpreter();

  test('parses a complete Arabic on-account sale into bounded structured intent', () {
    final intent = interpreter.interpret(
      'أنشئ فاتورة مبيعات لصنف السدر عبوة كيلو، بكمية 1، والوحدة جالون، بسعر 500 ريال سعودي، وعلى حساب محمد عبدالله باحكم',
    );

    expect(intent, isA<CreateSaleConversationIntent>());
    final sale = (intent as CreateSaleConversationIntent).sale;
    expect(sale.productQuery, 'السدر عبوة كيلو');
    expect(sale.quantityText, '1');
    expect(sale.unitQuery, 'جالون');
    expect(sale.unitPriceText, '500');
    expect(sale.currencyCode, 'SAR');
    expect(sale.customerQuery, 'محمد عبدالله باحكم');
    expect(sale.settlementMode, 'credit');
  });

  test('supports common Arabic quantity words while keeping canonical numeric output', () {
    final intent = interpreter.interpret(
      'انشئ فاتورة بيع لصنف سدر، بكمية واحد، الوحدة جالون، بسعر 80 ريال يمني، على حساب زبون عام',
    );
    final sale = (intent as CreateSaleConversationIntent).sale;
    expect(sale.quantityText, '1');
    expect(sale.currencyCode, 'YER');
    expect(sale.settlementMode, 'credit');
  });

  test('recognizes an explicit cash sale', () {
    final intent = interpreter.interpret(
      'أنشئ فاتورة بيع لصنف سدر، بكمية 2، الوحدة جالون، بسعر 100 ريال يمني، للعميل زبون عام، نقدًا',
    );
    final sale = (intent as CreateSaleConversationIntent).sale;
    expect(sale.settlementMode, 'cash');
    expect(sale.customerQuery, 'زبون عام');
  });

  test('refuses to guess settlement mode when neither cash nor credit is explicit', () {
    expect(
      () => interpreter.interpret(
        'أنشئ فاتورة بيع لصنف سدر، بكمية 1، الوحدة جالون، بسعر 100 ريال يمني، للعميل زبون عام',
      ),
      throwsA(
        isA<DomainError>().having((error) => error.code, 'code', 'SALE_INTENT_SETTLEMENT_REQUIRED'),
      ),
    );
  });

  test('recognizes safe lifecycle commands', () {
    expect(interpreter.interpret('اعتمدها'), isA<ApproveSaleDraftIntent>());
    expect(interpreter.interpret('رحّل الفاتورة'), isA<PostSaleDraftIntent>());
    expect(interpreter.interpret('إلغاء المسودة'), isA<CancelSaleDraftIntent>());
    expect(interpreter.interpret('اجعل السعر 400'), isA<ReviseSalePriceIntent>());
    expect(interpreter.interpret('عدّل الكمية 2'), isA<ReviseSaleQuantityIntent>());
  });

  test('does not invent an unsupported intent', () {
    expect(interpreter.interpret('افعل شيئا مناسبا'), isA<UnsupportedSaleIntent>());
  });
}
