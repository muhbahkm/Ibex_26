import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/agent/revise_sale_draft_service.dart';
import 'package:ibex_foundation_spike/core/errors/domain_error.dart';

OperationalDraft _draft({OperationalDraftState state = OperationalDraftState.awaitingApproval}) {
  var draft = OperationalDraft(
    draftId: 'draft-sale-1',
    commandName: 'CreateSaleDraft',
    version: 1,
    payload: const {
      'customer_id': 'customer-1',
      'customer_name': 'محمد عبدالله باحكم',
      'warehouse_id': 'warehouse-main',
      'currency_code': 'SAR',
      'lines': [
        {
          'product_id': 'product-1',
          'product_name': 'سدر — عبوة كيلو',
          'unit_id': 'unit-1',
          'unit_name': 'جالون',
          'quantity_scaled': 1000000,
          'quantity_precision': 0,
          'unit_price_scaled': 5000000,
        }
      ],
    },
    state: OperationalDraftState.draftReady,
    createdAtUtc: DateTime.utc(2026, 8, 11, 10),
  ).markAwaitingApproval();

  if (state == OperationalDraftState.approved) {
    draft = draft.approve();
  } else if (state == OperationalDraftState.cancelled) {
    draft = draft.cancel();
  }
  return draft;
}

void main() {
  const service = ReviseSaleDraftService();

  test('material price revision increments version and invalidates prior approval', () {
    final approved = _draft(state: OperationalDraftState.approved);
    final revised = service.execute(
      ReviseSaleDraftRequest(draft: approved, unitPriceText: '400'),
    );

    expect(revised.version, 2);
    expect(revised.state, OperationalDraftState.awaitingApproval);
    expect(revised.approvedFingerprint, isNull);
    expect(revised.fingerprint, isNot(approved.fingerprint));

    final line = (revised.payload['lines']! as List).single as Map;
    expect(line['unit_price_scaled'], 4000000);
    expect(line['quantity_scaled'], 1000000);
  });

  test('quantity revision keeps exact unit precision and requires new approval', () {
    final revised = service.execute(
      ReviseSaleDraftRequest(draft: _draft(), quantityText: '2'),
    );

    final line = (revised.payload['lines']! as List).single as Map;
    expect(revised.version, 2);
    expect(revised.state, OperationalDraftState.awaitingApproval);
    expect(line['quantity_scaled'], 2000000);
  });

  test('zero price is rejected before draft revision', () {
    expect(
      () => service.execute(
        ReviseSaleDraftRequest(draft: _draft(), unitPriceText: '0'),
      ),
      throwsA(
        isA<DomainError>().having((error) => error.code, 'code', 'SALE_DRAFT_PRICE_INVALID'),
      ),
    );
  });

  test('cancelled draft cannot be revised', () {
    expect(
      () => service.execute(
        ReviseSaleDraftRequest(
          draft: _draft(state: OperationalDraftState.cancelled),
          unitPriceText: '400',
        ),
      ),
      throwsA(
        isA<DomainError>().having((error) => error.code, 'code', 'DRAFT_TERMINAL_STATE'),
      ),
    );
  });
}
