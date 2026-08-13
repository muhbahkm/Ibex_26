import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/queries/operational_read_intent_interpreter.dart';

void main() {
  const interpreter = OperationalReadIntentInterpreter();

  test('parses Arabic customer balance read intent without inventing names', () {
    final intent = interpreter.interpret('كم رصيد محمد عبدالله؟');
    expect(intent, isA<CustomerBalanceReadIntent>());
    expect((intent as CustomerBalanceReadIntent).customerQuery, 'محمد عبدالله');
  });

  test('parses supplier balance before generic customer balance intent', () {
    final intent = interpreter.interpret('كم رصيد المورد مورد العسل؟');
    expect(intent, isA<SupplierBalanceReadIntent>());
    expect((intent as SupplierBalanceReadIntent).supplierQuery, 'مورد العسل');
  });

  test('supports natural supplier payable wording', () {
    final intent = interpreter.interpret('كم علينا للمورد مورد العسل؟');
    expect(intent, isA<SupplierBalanceReadIntent>());
    expect((intent as SupplierBalanceReadIntent).supplierQuery, 'مورد العسل');
  });

  test('parses Arabic inventory read intent and strips optional entity word', () {
    final intent = interpreter.interpret('اعرض مخزون الصنف سدر عبوة كيلو.');
    expect(intent, isA<InventoryBalanceReadIntent>());
    expect((intent as InventoryBalanceReadIntent).productQuery, 'سدر عبوة كيلو');
  });

  test('does not classify unrelated operational text as a read query', () {
    expect(
      interpreter.interpret('أنشئ فاتورة بيع جديدة'),
      isA<UnsupportedOperationalReadIntent>(),
    );
  });
}
