import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/approved_sale_draft_to_command.dart';
import 'package:ibex_foundation_spike/agent/command_registry.dart';
import 'package:ibex_foundation_spike/agent/create_sale_draft_service.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/agent/operational_draft_repository.dart';
import 'package:ibex_foundation_spike/agent/sale_operational_workflow.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_service.dart';

class _Catalog implements SaleDraftCatalog {
  const _Catalog();

  @override
  Future<List<SaleDraftCustomer>> findCustomers(String query) async => const [
        SaleDraftCustomer(id: 'CUSTOMER-1', name: 'محمد عبدالله باحكم'),
      ];

  @override
  Future<List<SaleDraftProduct>> findProducts(String query) async => const [
        SaleDraftProduct(id: 'P-1', name: 'سدر — عبوة كيلو'),
      ];

  @override
  Future<List<SaleDraftUnit>> findUnitsForProduct(String productId, String query) async => const [
        SaleDraftUnit(id: 'UNIT-1', name: 'جالون', quantityPrecision: 0),
      ];
}

CreateSaleDraftRequest _request({String settlementMode = 'cash'}) => CreateSaleDraftRequest(
      draftId: 'draft-flow-1',
      customerQuery: 'محمد عبدالله باحكم',
      productQuery: 'سدر',
      unitQuery: 'جالون',
      quantityText: '1',
      unitPriceText: '80',
      currencyCode: 'YER',
      warehouseId: 'WH-1',
      createdAtUtc: DateTime.utc(2026, 8, 11, 10),
      settlementMode: settlementMode,
    );

final _postingContext = SalePostingContext(
  operationId: 'op-workflow-1',
  businessId: 'B-1',
  userId: 'U-1',
  baseCurrencyCode: 'YER',
  exchangeRateScaled: 100000000,
  cashAccountId: 'CASH-1',
  cashLedgerAccountId: 'ACC-CASH',
  salesRevenueAccountId: 'ACC-SALES',
  inventoryLedgerAccountId: 'ACC-INV',
  cogsLedgerAccountId: 'ACC-COGS',
  saleAt: DateTime.utc(2026, 8, 11, 10),
);

Future<void> _seedStock(SpikeDatabase db) async {
  await db.into(db.inventoryBalances).insert(
        InventoryBalancesCompanion.insert(
          warehouseId: 'WH-1',
          productId: 'P-1',
          quantityScaled: 10 * 1000000,
          inventoryValueScaled: 500 * 10000,
          wacUnitCostScaled: 50 * 10000,
          updatedAt: DateTime.utc(2026, 8, 11),
        ),
      );
}

SaleOperationalWorkflow _workflow(
  SpikeDatabase db, {
  PostSaleService? postSaleService,
}) {
  return SaleOperationalWorkflow(
    createSaleDraft: CreateSaleDraftService(
      catalog: const _Catalog(),
      registry: const AgentCommandRegistry({CreateSaleDraftService.commandName}),
    ),
    draftRepository: OperationalDraftRepository(db),
    postSaleService: postSaleService ?? PostSaleService(db),
  );
}

void main() {
  late SpikeDatabase db;

  setUp(() async {
    db = SpikeDatabase.inMemory();
    await _seedStock(db);
  });

  tearDown(() => db.close());

  test('create approve and post persists lifecycle and commits canonical cash truth', () async {
    final workflow = _workflow(db);

    final created = await workflow.create(_request());
    expect(created.state, OperationalDraftState.awaitingApproval);
    expect((await workflow.loadRequired(created.draftId)).version, 1);

    final approved = await workflow.approve(created.draftId);
    expect(approved.state, OperationalDraftState.approved);
    expect(approved.approvedFingerprint, approved.fingerprint);

    final result = await workflow.postApproved(
      draftId: created.draftId,
      context: _postingContext,
    );
    expect(result.documentNo, 'SAL-2026-000001');
    expect(result.idempotentReplay, isFalse);
    expect(result.paymentId, isNotNull);

    final stored = await workflow.loadRequired(created.draftId);
    expect(stored.state, OperationalDraftState.posted);
    expect((await db.select(db.sales).get()), hasLength(1));
    expect((await db.select(db.journalEntries).get()), hasLength(1));
    expect((await db.select(db.journalLines).get()), hasLength(4));
    expect((await db.select(db.stockMovements).get()), hasLength(1));
    expect((await db.select(db.payments).get()), hasLength(1));
    expect((await db.select(db.customerLedger).get()), isEmpty);
    expect((await db.select(db.auditLogs).get()), hasLength(1));

    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 9 * 1000000);
    expect(balance.inventoryValueScaled, 450 * 10000);
  });

  test('credit workflow posts receivable and customer ledger without cash payment', () async {
    final workflow = _workflow(db);
    final created = await workflow.create(_request(settlementMode: 'credit'));
    await workflow.approve(created.draftId);

    final result = await workflow.postApproved(
      draftId: created.draftId,
      context: _postingContext,
    );
    expect(result.paymentId, isNull);
    expect(await db.select(db.payments).get(), isEmpty);

    final sale = await db.select(db.sales).getSingle();
    expect(sale.customerId, 'CUSTOMER-1');
    expect(sale.settlementMode, 'credit');

    final customerEntry = await db.select(db.customerLedger).getSingle();
    expect(customerEntry.customerId, 'CUSTOMER-1');
    expect(customerEntry.debitScaled, 80 * 10000);
    expect(customerEntry.creditScaled, 0);

    final journal = await db.select(db.journalLines).get();
    expect(
      journal.any((line) => line.accountId == 'ACC-AR' && line.baseDebitScaled == 80 * 10000),
      isTrue,
    );
  });

  test('posting failure leaves persisted draft approved and canonical truth untouched', () async {
    final failingPost = PostSaleService(
      db,
      failureInjector: (point) {
        if (point == 'before_commit') throw StateError('injected posting failure');
      },
    );
    final workflow = _workflow(db, postSaleService: failingPost);

    final created = await workflow.create(_request());
    await workflow.approve(created.draftId);

    await expectLater(
      workflow.postApproved(draftId: created.draftId, context: _postingContext),
      throwsStateError,
    );

    final stored = await workflow.loadRequired(created.draftId);
    expect(stored.state, OperationalDraftState.approved);
    stored.requireValidApprovalForPosting();
    expect(await db.select(db.sales).get(), isEmpty);
    expect(await db.select(db.journalEntries).get(), isEmpty);
    expect(await db.select(db.stockMovements).get(), isEmpty);
    expect(await db.select(db.payments).get(), isEmpty);
    expect(await db.select(db.customerLedger).get(), isEmpty);

    final balance = await db.select(db.inventoryBalances).getSingle();
    expect(balance.quantityScaled, 10 * 1000000);
  });

  test('material revision is persisted and blocks posting until fresh approval', () async {
    final workflow = _workflow(db);
    final created = await workflow.create(_request());
    await workflow.approve(created.draftId);

    final revised = await workflow.revisePrice(created.draftId, '75');
    expect(revised.version, 2);
    expect(revised.state, OperationalDraftState.awaitingApproval);
    expect(revised.approvedFingerprint, isNull);

    await expectLater(
      workflow.postApproved(draftId: created.draftId, context: _postingContext),
      throwsA(anything),
    );
    expect(await db.select(db.sales).get(), isEmpty);

    await workflow.approve(created.draftId);
    final result = await workflow.postApproved(
      draftId: created.draftId,
      context: _postingContext,
    );
    expect(result.documentNo, 'SAL-2026-000001');
    final sale = await db.select(db.sales).getSingle();
    expect(sale.totalScaled, 75 * 10000);
  });
}
