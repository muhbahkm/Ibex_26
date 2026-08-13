import '../core/errors/domain_error.dart';

class ParsedSaleCreateIntent {
  const ParsedSaleCreateIntent({
    required this.customerQuery,
    required this.productQuery,
    required this.unitQuery,
    required this.quantityText,
    required this.unitPriceText,
    required this.currencyCode,
    required this.settlementMode,
  });

  final String customerQuery;
  final String productQuery;
  final String unitQuery;
  final String quantityText;
  final String unitPriceText;
  final String currencyCode;
  final String settlementMode;
}

sealed class SaleConversationIntent {
  const SaleConversationIntent();
}

class CreateSaleConversationIntent extends SaleConversationIntent {
  const CreateSaleConversationIntent(this.sale);
  final ParsedSaleCreateIntent sale;
}

class ReviseSalePriceIntent extends SaleConversationIntent {
  const ReviseSalePriceIntent(this.priceText);
  final String priceText;
}

class ReviseSaleQuantityIntent extends SaleConversationIntent {
  const ReviseSaleQuantityIntent(this.quantityText);
  final String quantityText;
}

class ApproveSaleDraftIntent extends SaleConversationIntent {
  const ApproveSaleDraftIntent();
}

class CancelSaleDraftIntent extends SaleConversationIntent {
  const CancelSaleDraftIntent();
}

class PostSaleDraftIntent extends SaleConversationIntent {
  const PostSaleDraftIntent();
}

class UnsupportedSaleIntent extends SaleConversationIntent {
  const UnsupportedSaleIntent();
}

class SaleIntentInterpreter {
  const SaleIntentInterpreter();

  SaleConversationIntent interpret(String input) {
    final text = _normalizeSpacing(input);
    if (text.isEmpty) return const UnsupportedSaleIntent();

    if (_matchesAny(text, const ['الغ المسودة', 'ألغي المسودة', 'إلغاء المسودة', 'الغي الفاتورة'])) {
      return const CancelSaleDraftIntent();
    }
    if (_matchesAny(text, const ['رحل الفاتورة', 'رحّل الفاتورة', 'اعتمد نهائيا', 'اعتمد نهائيًا', 'نفذ الفاتورة', 'نفّذ الفاتورة'])) {
      return const PostSaleDraftIntent();
    }
    if (_matchesAny(text, const ['اعتمدها', 'اعتماد', 'وافق عليها', 'موافق عليها'])) {
      return const ApproveSaleDraftIntent();
    }

    final priceRevision = _extractSingleNumberAfter(
      text,
      const ['اجعل المبلغ', 'اجعل السعر', 'عدل السعر', 'عدّل السعر', 'غير السعر', 'غيّر السعر'],
      maxDecimals: 4,
    );
    if (priceRevision != null) return ReviseSalePriceIntent(priceRevision);

    final quantityRevision = _extractQuantityAfter(
      text,
      const ['اجعل الكمية', 'عدل الكمية', 'عدّل الكمية', 'غير الكمية', 'غيّر الكمية'],
    );
    if (quantityRevision != null) return ReviseSaleQuantityIntent(quantityRevision);

    final looksLikeCreate = text.contains('فاتورة') &&
        (text.contains('بيع') || text.contains('مبيعات')) &&
        (text.contains('أنشئ') || text.contains('انشئ') || text.contains('أنشء') || text.contains('اعمل'));
    if (!looksLikeCreate) return const UnsupportedSaleIntent();

    return CreateSaleConversationIntent(_parseCreate(text));
  }

  ParsedSaleCreateIntent _parseCreate(String text) {
    final price = _extractPrice(text);
    final quantity = _extractQuantity(text);
    final currency = _extractCurrency(text);
    final settlementMode = _extractSettlementMode(text);
    final unit = _captureAfterKeyword(
      text,
      const ['الوحدة', 'بوحدة', 'وحدة'],
      stopWords: const ['على حساب', 'للعميل', 'العميل', 'بسعر', 'السعر', 'بكمية', 'الكمية', 'نقدا', 'نقدًا'],
    );
    final customer = _captureAfterKeyword(
      text,
      const ['على حساب', 'للعميل', 'العميل'],
      stopWords: const ['بسعر', 'السعر', 'بكمية', 'الكمية', 'الوحدة', 'نقدا', 'نقدًا'],
    );
    final product = _captureAfterKeyword(
      text,
      const ['لصنف', 'الصنف', 'صنف'],
      stopWords: const [
        'بسعر',
        'السعر',
        'بكمية',
        'الكمية',
        'الوحدة',
        'على حساب',
        'للعميل',
        'العميل',
        'نقدا',
        'نقدًا',
      ],
    );

    if (price == null) {
      throw const DomainError('SALE_INTENT_PRICE_REQUIRED', 'Sale command must include one explicit price.');
    }
    if (quantity == null) {
      throw const DomainError('SALE_INTENT_QUANTITY_REQUIRED', 'Sale command must include one explicit quantity.');
    }
    if (currency == null) {
      throw const DomainError('SALE_INTENT_CURRENCY_REQUIRED', 'Sale command must include a supported currency.');
    }
    if (settlementMode == null) {
      throw const DomainError(
        'SALE_INTENT_SETTLEMENT_REQUIRED',
        'Sale command must explicitly indicate cash or on-account settlement.',
      );
    }
    if (unit == null || unit.isEmpty) {
      throw const DomainError('SALE_INTENT_UNIT_REQUIRED', 'Sale command must include a unit.');
    }
    if (customer == null || customer.isEmpty) {
      throw const DomainError('SALE_INTENT_CUSTOMER_REQUIRED', 'Sale command must include a customer.');
    }
    if (product == null || product.isEmpty) {
      throw const DomainError('SALE_INTENT_PRODUCT_REQUIRED', 'Sale command must include a product.');
    }

    return ParsedSaleCreateIntent(
      customerQuery: customer,
      productQuery: product,
      unitQuery: unit,
      quantityText: quantity,
      unitPriceText: price,
      currencyCode: currency,
      settlementMode: settlementMode,
    );
  }

  String? _extractSettlementMode(String text) {
    final credit = text.contains('على حساب') || text.contains('آجل') || text.contains('اجل');
    final cash = text.contains('نقدا') || text.contains('نقدًا') || text.contains('نقدي') || text.contains('كاش');
    if (credit == cash) return null;
    return credit ? 'credit' : 'cash';
  }

  String? _extractPrice(String text) {
    final direct = _extractSingleNumberAfter(
      text,
      const ['بسعر', 'السعر', 'سعر'],
      maxDecimals: 4,
    );
    if (direct != null) return direct;

    final currencyPattern = RegExp(
      r'(?<![\d.])(\d+(?:\.\d{1,4})?)\s*(?:ريال\s+سعودي|ريال\s+يمني|دولار|SAR|YER|USD)\b',
      caseSensitive: false,
    );
    final matches = currencyPattern.allMatches(text).toList();
    return matches.length == 1 ? matches.single.group(1) : null;
  }

  String? _extractQuantity(String text) {
    return _extractQuantityAfter(text, const ['بكمية', 'الكمية', 'كمية']);
  }

  String? _extractQuantityAfter(String text, List<String> prefixes) {
    for (final prefix in prefixes) {
      final index = text.indexOf(prefix);
      if (index < 0) continue;
      final rest = text.substring(index + prefix.length).trimLeft();
      final numeric = RegExp(r'^(\d+(?:\.\d{1,6})?)').firstMatch(rest)?.group(1);
      if (numeric != null) return numeric;
      final word = rest.split(RegExp(r'[\s،,.;]+')).firstOrNull;
      final mapped = _numberWords[word];
      if (mapped != null) return mapped;
    }
    return null;
  }

  String? _extractCurrency(String text) {
    final matches = <String>{};
    if (RegExp(r'ريال\s+سعودي|\bSAR\b', caseSensitive: false).hasMatch(text)) matches.add('SAR');
    if (RegExp(r'ريال\s+يمني|\bYER\b', caseSensitive: false).hasMatch(text)) matches.add('YER');
    if (RegExp(r'دولار(?:\s+امريكي|\s+أمريكي)?|\bUSD\b', caseSensitive: false).hasMatch(text)) matches.add('USD');
    if (matches.length != 1) return null;
    return matches.single;
  }

  String? _extractSingleNumberAfter(
    String text,
    List<String> prefixes, {
    required int maxDecimals,
  }) {
    final values = <String>[];
    final decimalPart = maxDecimals > 0 ? r'(?:\.\d{1,' + '$maxDecimals' + r'})?' : '';
    for (final prefix in prefixes) {
      var from = 0;
      while (true) {
        final index = text.indexOf(prefix, from);
        if (index < 0) break;
        final rest = text.substring(index + prefix.length).trimLeft();
        final match = RegExp('^(\\d+$decimalPart)').firstMatch(rest);
        if (match != null) values.add(match.group(1)!);
        from = index + prefix.length;
      }
    }
    final unique = values.toSet();
    return unique.length == 1 ? unique.single : null;
  }

  String? _captureAfterKeyword(
    String text,
    List<String> keywords, {
    required List<String> stopWords,
  }) {
    var bestIndex = -1;
    String? bestKeyword;
    for (final keyword in keywords) {
      final index = text.indexOf(keyword);
      if (index >= 0 && (bestIndex < 0 || index < bestIndex)) {
        bestIndex = index;
        bestKeyword = keyword;
      }
    }
    if (bestKeyword == null) return null;

    var rest = text.substring(bestIndex + bestKeyword.length).trimLeft();
    var end = rest.length;
    for (final stop in stopWords) {
      final stopIndex = rest.indexOf(stop);
      if (stopIndex >= 0 && stopIndex < end) end = stopIndex;
    }
    final punctuation = RegExp(r'[،,;\n]').firstMatch(rest);
    if (punctuation != null && punctuation.start < end) end = punctuation.start;
    rest = rest.substring(0, end).trim();
    return rest.replaceFirst(RegExp(r'^[\s:：-]+'), '').replaceFirst(RegExp(r'[\s.]+$'), '');
  }

  bool _matchesAny(String text, List<String> phrases) => phrases.any(text.contains);

  String _normalizeSpacing(String input) => input.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _numberWords = <String, String>{
  'واحد': '1',
  'واحدة': '1',
  'اثنين': '2',
  'اثنان': '2',
  'اثنتين': '2',
  'ثلاثة': '3',
  'ثلاث': '3',
  'اربعة': '4',
  'أربعة': '4',
  'خمس': '5',
  'خمسة': '5',
  'ست': '6',
  'ستة': '6',
  'سبع': '7',
  'سبعة': '7',
  'ثمان': '8',
  'ثمانية': '8',
  'تسع': '9',
  'تسعة': '9',
  'عشر': '10',
  'عشرة': '10',
};
