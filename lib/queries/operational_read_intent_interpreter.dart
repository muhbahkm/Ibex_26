sealed class OperationalReadIntent {
  const OperationalReadIntent();
}

class CustomerBalanceReadIntent extends OperationalReadIntent {
  const CustomerBalanceReadIntent(this.customerQuery);
  final String customerQuery;
}

class SupplierBalanceReadIntent extends OperationalReadIntent {
  const SupplierBalanceReadIntent(this.supplierQuery);
  final String supplierQuery;
}

class InventoryBalanceReadIntent extends OperationalReadIntent {
  const InventoryBalanceReadIntent(this.productQuery);
  final String productQuery;
}

class UnsupportedOperationalReadIntent extends OperationalReadIntent {
  const UnsupportedOperationalReadIntent();
}

class OperationalReadIntentInterpreter {
  const OperationalReadIntentInterpreter();

  OperationalReadIntent interpret(String input) {
    final text = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return const UnsupportedOperationalReadIntent();

    final supplierQuery = _extractAfterPrefixes(
      text,
      const [
        'كم رصيد المورد',
        'ما رصيد المورد',
        'اعرض رصيد المورد',
        'أعرض رصيد المورد',
        'كم علينا للمورد',
        'ما علينا للمورد',
      ],
    );
    if (supplierQuery != null) {
      return SupplierBalanceReadIntent(supplierQuery);
    }

    final customerQuery = _extractAfterPrefixes(
      text,
      const [
        'كم رصيد',
        'ما رصيد',
        'اعرض رصيد',
        'أعرض رصيد',
        'رصيد العميل',
        'رصيد الزبون',
      ],
    );
    if (customerQuery != null) {
      return CustomerBalanceReadIntent(customerQuery);
    }

    final productQuery = _extractAfterPrefixes(
      text,
      const [
        'كم مخزون',
        'ما مخزون',
        'اعرض مخزون',
        'أعرض مخزون',
        'رصيد مخزون',
      ],
    );
    if (productQuery != null) {
      return InventoryBalanceReadIntent(productQuery);
    }

    return const UnsupportedOperationalReadIntent();
  }

  String? _extractAfterPrefixes(String text, List<String> prefixes) {
    for (final prefix in prefixes) {
      if (!text.startsWith(prefix)) continue;
      var value = text.substring(prefix.length).trim();
      value = value
          .replaceFirst(RegExp(r'^(?:العميل|الزبون|المورد|الصنف)\s+'), '')
          .replaceFirst(RegExp(r'[؟?!.،,]+$'), '')
          .trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }
}
