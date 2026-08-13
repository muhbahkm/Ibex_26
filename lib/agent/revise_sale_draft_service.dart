import '../core/errors/domain_error.dart';
import '../core/value_objects/money.dart';
import '../core/value_objects/quantity.dart';
import 'operational_draft.dart';

class ReviseSaleDraftRequest {
  const ReviseSaleDraftRequest({
    required this.draft,
    this.quantityText,
    this.unitPriceText,
  });

  final OperationalDraft draft;
  final String? quantityText;
  final String? unitPriceText;
}

class ReviseSaleDraftService {
  const ReviseSaleDraftService();

  OperationalDraft execute(ReviseSaleDraftRequest request) {
    final draft = request.draft;
    if (draft.commandName != 'CreateSaleDraft') {
      throw const DomainError(
        'SALE_DRAFT_COMMAND_INVALID',
        'Only CreateSaleDraft drafts can be revised by this service.',
      );
    }

    final linesValue = draft.payload['lines'];
    if (linesValue is! List || linesValue.length != 1) {
      throw const DomainError(
        'SALE_DRAFT_LINE_SHAPE_UNSUPPORTED',
        'This spike revision service currently supports exactly one sale line.',
      );
    }

    final rawLine = linesValue.single;
    if (rawLine is! Map) {
      throw const DomainError(
        'SALE_DRAFT_LINE_INVALID',
        'Sale draft line payload is invalid.',
      );
    }

    final line = <String, Object?>{
      for (final entry in rawLine.entries) entry.key.toString(): entry.value,
    };
    final currency = draft.payload['currency_code'];
    final precision = line['quantity_precision'];
    final existingQty = line['quantity_scaled'];
    final existingPrice = line['unit_price_scaled'];

    if (currency is! String ||
        precision is! int ||
        existingQty is! int ||
        existingPrice is! int) {
      throw const DomainError(
        'SALE_DRAFT_PAYLOAD_INVALID',
        'Sale draft payload is missing required typed values.',
      );
    }

    if (request.quantityText != null) {
      final quantity = Quantity.parseExact(
        request.quantityText!,
        allowedDecimals: precision,
      );
      if (quantity.isZero || quantity.isNegative) {
        throw const DomainError(
          'SALE_DRAFT_QUANTITY_INVALID',
          'Sale draft quantity must be greater than zero.',
        );
      }
      line['quantity_scaled'] = quantity.scaled;
    }

    if (request.unitPriceText != null) {
      final price = Money.parseExact(request.unitPriceText!, currency);
      if (price.isZero || price.isNegative) {
        throw const DomainError(
          'SALE_DRAFT_PRICE_INVALID',
          'Sale draft unit price must be greater than zero.',
        );
      }
      line['unit_price_scaled'] = price.scaled;
    }

    if (request.quantityText == null && request.unitPriceText == null) {
      throw const DomainError(
        'SALE_DRAFT_NO_CHANGES',
        'At least one material sale draft field must change.',
      );
    }

    final nextPayload = <String, Object?>{
      for (final entry in draft.payload.entries)
        entry.key: entry.key == 'lines' ? [Map.unmodifiable(line)] : entry.value,
    };

    return draft.revise(Map.unmodifiable(nextPayload)).markAwaitingApproval();
  }
}
