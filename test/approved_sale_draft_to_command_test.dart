import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/approved_sale_draft_to_command.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/core/errors/domain_error.dart';

OperationalDraft _saleDraft() => OperationalDraft(
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

final _context = SalePostingContext(
  operationId: 'op-sale-draft-1',
  businessId: 'business-1',
  userId: 'user-1',
  baseCurrencyCode: 'YER',
  exchangeRateScaled: 6500000000,
  cashAccountId: 'cash-1',
  cashLedgerAccountId: 'ledger-cash',
  salesRevenueAccountId: 'ledger-sales',
  inventoryLedgerAccountId: 'ledger-inventory',
  cogsLedgerAccountId: 'ledger-cogs',
  saleAt: DateTime.utc(2026, 8, 11, 10),
);

void main() {
  const mapper = ApprovedSaleDraftToCommand();

  test('approved draft maps to a typed PostSale command without posting', () {
    final draft = _saleDraft().approve();
    final command = mapper.build(draft: draft, context: _context);

    expect(command.operationId, 'op-sale-draft-1');
    expect(command.businessId, 'business-1');
    expect(command.warehouseId, 'warehouse-main');
    expect(command.currencyCode, 'SAR');
    expect(command.baseCurrencyCode, 'YER');
    expect(command.lines.single.productId, 'product-1');
    expect(command.lines.single.quantityScaled, 1000000);
    expect(command.lines.single.unitPriceScaled, 5000000);
  });

  test('unapproved draft cannot become a PostSale command', () {
    expect(
      () => mapper.build(draft: _saleDraft(), context: _context),
      throwsA(
        isA<DomainError>().having((error) => error.code, 'code', 'DRAFT_APPROVAL_REQUIRED'),
      ),
    );
  });

  test('materially revised draft requires fresh approval before command mapping', () {
    final approved = _saleDraft().approve();
    final revised = approved.revise({
      ...approved.payload,
      'currency_code': 'USD',
    }).markAwaitingApproval();

    expect(
      () => mapper.build(draft: revised, context: _context),
      throwsA(
        isA<DomainError>().having((error) => error.code, 'code', 'DRAFT_APPROVAL_REQUIRED'),
      ),
    );
  });
}
