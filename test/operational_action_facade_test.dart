import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/command_registry.dart';
import 'package:ibex_foundation_spike/agent/operational_action_facade.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';
import 'package:ibex_foundation_spike/operating_engine/pay_supplier_command.dart';
import 'package:ibex_foundation_spike/operating_engine/pay_supplier_service.dart';
import 'package:ibex_foundation_spike/operating_engine/post_expense_service.dart';
import 'package:ibex_foundation_spike/operating_engine/post_purchase_return_service.dart';
import 'package:ibex_foundation_spike/operating_engine/post_purchase_service.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_command.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_return_service.dart';
import 'package:ibex_foundation_spike/operating_engine/post_sale_service.dart';
import 'package:ibex_foundation_spike/operating_engine/receive_customer_payment_command.dart';
import 'package:ibex_foundation_spike/operating_engine/receive_customer_payment_service.dart';
import 'package:ibex_foundation_spike/operating_engine/reverse_expense_command.dart';
import 'package:ibex_foundation_spike/operating_engine/reverse_expense_service.dart';
import 'package:ibex_foundation_spike/operating_engine/transfer_stock_service.dart';
import 'package:ibex_foundation_spike/security/authorization_service.dart';

void main() {
  test('unregistered write is rejected before authorization or engine mutation', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final facade = _facade(db, registry: const AgentCommandRegistry({}));

    final command = _payCommand(operationId: 'OP-BLOCKED');
    await expectLater(facade.executePaySupplier(command), throwsA(isA<Exception>()));
    expect(await db.select(db.supplierPayments).get(), isEmpty);
    expect(await db.select(db.operationLog).get(), isEmpty);
  });

  test('registered write is denied when active user lacks permission', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 11);
    await _insertActiveUser(db, now);
    final facade = _facade(
      db,
      registry: const AgentCommandRegistry({OperationalActionFacade.paySupplierCommand}),
    );

    await expectLater(
      facade.executePaySupplier(_payCommand(operationId: 'OP-DENIED')),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.supplierPayments).get(), isEmpty);
    expect(await db.select(db.operationLog).get(), isEmpty);
  });

  test('business-scoped role permission allows registered write to reach engine', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 11);
    await _grant(db, now, OperationalPermissions.paySupplier);

    final facade = _facade(
      db,
      registry: const AgentCommandRegistry({OperationalActionFacade.paySupplierCommand}),
    );

    await expectLater(
      facade.executePaySupplier(_payCommand(operationId: 'OP-AUTHORIZED')),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.supplierPayments).get(), isEmpty);
    expect(await db.select(db.operationLog).get(), isEmpty);
  });

  test('sale posting is denied before stock or accounting mutation without sale permission', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 11);
    await _insertActiveUser(db, now);
    final facade = _facade(
      db,
      registry: const AgentCommandRegistry({OperationalActionFacade.postSaleCommand}),
    );

    await expectLater(
      facade.executePostSale(_saleCommand(operationId: 'OP-SALE-DENIED')),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.sales).get(), isEmpty);
    expect(await db.select(db.stockMovements).get(), isEmpty);
    expect(await db.select(db.journalEntries).get(), isEmpty);
    expect(await db.select(db.operationLog).get(), isEmpty);
  });

  test('customer receipt is denied before ledger or journal mutation without permission', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 11);
    await _insertActiveUser(db, now);
    final facade = _facade(
      db,
      registry: const AgentCommandRegistry({
        OperationalActionFacade.receiveCustomerPaymentCommand,
      }),
    );

    await expectLater(
      facade.executeReceiveCustomerPayment(
        _receiptCommand(operationId: 'OP-RCT-DENIED'),
      ),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.customerReceipts).get(), isEmpty);
    expect(await db.select(db.customerLedger).get(), isEmpty);
    expect(await db.select(db.journalEntries).get(), isEmpty);
    expect(await db.select(db.operationLog).get(), isEmpty);
  });

  test('expense reversal is denied before source lookup or compensating mutation', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 8, 11);
    await _insertActiveUser(db, now);
    final facade = _facade(
      db,
      registry: const AgentCommandRegistry({
        OperationalActionFacade.reverseExpenseCommand,
      }),
    );

    await expectLater(
      facade.executeReverseExpense(
        ReverseExpenseCommand(
          operationId: 'OP-EXR-DENIED',
          businessId: 'B-1',
          userId: 'U-1',
          sourceExpenseId: 'EXP-NOT-LOOKED-UP',
          reason: 'اختبار الصلاحية',
          reversedAt: now,
        ),
      ),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.expenseReversals).get(), isEmpty);
    expect(await db.select(db.journalEntries).get(), isEmpty);
    expect(await db.select(db.operationLog).get(), isEmpty);
  });
}

Future<void> _insertActiveUser(SpikeDatabase db, DateTime now) async {
  await db.into(db.appUsers).insert(
        AppUsersCompanion.insert(
          id: 'U-1',
          businessId: 'B-1',
          displayName: 'مستخدم',
          updatedAt: now,
        ),
      );
}

Future<void> _grant(
  SpikeDatabase db,
  DateTime now,
  String permission,
) async {
  await _insertActiveUser(db, now);
  await db.into(db.roles).insert(
        RolesCompanion.insert(
          id: 'R-1',
          businessId: 'B-1',
          name: 'مدير التشغيل',
          updatedAt: now,
        ),
      );
  await db.into(db.userRoles).insert(
        const UserRolesCompanion(
          businessId: Value('B-1'),
          userId: Value('U-1'),
          roleId: Value('R-1'),
        ),
      );
  await db.into(db.rolePermissions).insert(
        RolePermissionsCompanion.insert(
          businessId: 'B-1',
          roleId: 'R-1',
          permission: permission,
        ),
      );
}

OperationalActionFacade _facade(
  SpikeDatabase db, {
  required AgentCommandRegistry registry,
}) =>
    OperationalActionFacade(
      registry: registry,
      authorization: AuthorizationService(db),
      postSale: PostSaleService(db),
      postPurchase: PostPurchaseService(db),
      receiveCustomerPayment: ReceiveCustomerPaymentService(db),
      paySupplier: PaySupplierService(db),
      transferStock: TransferStockService(db),
      postSaleReturn: PostSaleReturnService(db),
      postPurchaseReturn: PostPurchaseReturnService(db),
      postExpense: PostExpenseService(db),
      reverseExpense: ReverseExpenseService(db),
    );

PaySupplierCommand _payCommand({required String operationId}) => PaySupplierCommand(
      operationId: operationId,
      businessId: 'B-1',
      userId: 'U-1',
      supplierId: 'SUP-1',
      currencyCode: 'SAR',
      baseCurrencyCode: 'SAR',
      exchangeRateScaled: 100000000,
      amountScaled: 10000,
      cashAccountId: 'CASH-1',
      cashLedgerAccountId: 'ACC-CASH',
      accountsPayableLedgerAccountId: 'ACC-AP',
      paidAt: DateTime.utc(2026, 8, 11),
    );

PostSaleCommand _saleCommand({required String operationId}) => PostSaleCommand(
      operationId: operationId,
      businessId: 'B-1',
      userId: 'U-1',
      warehouseId: 'WH-1',
      settlementMode: SaleSettlementMode.cash,
      currencyCode: 'SAR',
      baseCurrencyCode: 'SAR',
      exchangeRateScaled: 100000000,
      cashAccountId: 'CASH-1',
      cashLedgerAccountId: 'ACC-CASH',
      salesRevenueAccountId: 'ACC-SALES',
      inventoryLedgerAccountId: 'ACC-INV',
      cogsLedgerAccountId: 'ACC-COGS',
      accountsReceivableLedgerAccountId: 'ACC-AR',
      saleAt: DateTime.utc(2026, 8, 11),
      lines: const [
        PostSaleLineInput(
          productId: 'P-1',
          quantityScaled: 1000000,
          unitPriceScaled: 10000,
        ),
      ],
    );

ReceiveCustomerPaymentCommand _receiptCommand({required String operationId}) =>
    ReceiveCustomerPaymentCommand(
      operationId: operationId,
      businessId: 'B-1',
      userId: 'U-1',
      customerId: 'C-1',
      currencyCode: 'SAR',
      baseCurrencyCode: 'SAR',
      exchangeRateScaled: 100000000,
      amountScaled: 10000,
      cashAccountId: 'CASH-1',
      cashLedgerAccountId: 'ACC-CASH',
      accountsReceivableLedgerAccountId: 'ACC-AR',
      receivedAt: DateTime.utc(2026, 8, 11),
    );
