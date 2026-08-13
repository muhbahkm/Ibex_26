enum AiOperationalAction {
  createSale,
  customerBalance,
  inventoryBalance,
  supplierBalance,
  unknown,
}

class AiOperationalIntent {
  const AiOperationalIntent({required this.action, required this.arguments});

  final AiOperationalAction action;
  final Map<String, String> arguments;

  String? argument(String key) => arguments[key]?.trim().isEmpty == true
      ? null
      : arguments[key]?.trim();
}

abstract interface class OperationalAiIntentResolver {
  Future<AiOperationalIntent?> resolve(String userText);
}
