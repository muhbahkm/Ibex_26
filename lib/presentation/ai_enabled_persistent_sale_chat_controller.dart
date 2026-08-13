import 'dart:async';

import '../agent/sale_intent_interpreter.dart';
import '../ai/operational_ai_intent.dart';
import '../core/errors/domain_error.dart';
import '../queries/operational_read_intent_interpreter.dart';
import 'persistent_sale_chat_controller.dart';

class AiEnabledPersistentSaleChatController extends PersistentSaleChatController {
  AiEnabledPersistentSaleChatController({
    required super.workflow,
    required super.postingContextFactory,
    required this.aiResolver,
    super.defaultWarehouseId,
    super.readQueries,
  });

  final OperationalAiIntentResolver aiResolver;
  final SaleIntentInterpreter _localSale = const SaleIntentInterpreter();
  final OperationalReadIntentInterpreter _localRead =
      const OperationalReadIntentInterpreter();

  @override
  void submitNaturalLanguage(String text) {
    final value = text.trim();
    if (value.isEmpty || busy) return;

    final read = _localRead.interpret(value);
    if (read is! UnsupportedOperationalReadIntent) {
      super.submitNaturalLanguage(value);
      return;
    }

    try {
      final sale = _localSale.interpret(value);
      if (sale is! UnsupportedSaleIntent) {
        super.submitNaturalLanguage(value);
        return;
      }
    } on DomainError {
      // Preserve the existing local validation/error path for sale-looking input.
      super.submitNaturalLanguage(value);
      return;
    }

    unawaited(_resolveAiFallback(value));
  }

  Future<void> _resolveAiFallback(String original) async {
    final intent = await aiResolver.resolve(original);
    final localCommand = _toLocalCommand(intent);
    super.submitNaturalLanguage(localCommand ?? original);
  }

  String? _toLocalCommand(AiOperationalIntent? intent) {
    if (intent == null) return null;
    switch (intent.action) {
      case AiOperationalAction.customerBalance:
        final customer = intent.argument('customer');
        return customer == null ? null : 'اعرض رصيد $customer';
      case AiOperationalAction.inventoryBalance:
        final product = intent.argument('product');
        return product == null ? null : 'اعرض مخزون $product';
      case AiOperationalAction.supplierBalance:
        final supplier = intent.argument('supplier');
        return supplier == null ? null : 'اعرض رصيد المورد $supplier';
      case AiOperationalAction.createSale:
        final customer = intent.argument('customer');
        final product = intent.argument('product');
        final unit = intent.argument('unit');
        final quantity = intent.argument('quantity');
        final price = intent.argument('unit_price');
        final currency = intent.argument('currency');
        if ([customer, product, unit, quantity, price, currency]
            .any((value) => value == null)) {
          return null;
        }
        final settlement = intent.argument('settlement_mode') ?? 'cash';
        final tail = settlement == 'credit'
            ? 'على حساب $customer'
            : 'للعميل $customer نقدًا';
        return 'أنشئ فاتورة بيع لصنف $product بكمية $quantity '
            'الوحدة $unit بسعر $price $currency $tail';
      case AiOperationalAction.unknown:
        return null;
    }
  }
}
