import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../agent/approved_sale_draft_to_command.dart';
import '../agent/command_registry.dart';
import '../agent/create_sale_draft_service.dart';
import '../agent/local_sale_draft_catalog.dart';
import '../agent/operational_action_facade.dart';
import '../agent/operational_draft.dart';
import '../agent/operational_draft_repository.dart';
import '../agent/sale_operational_workflow.dart';
import '../ai/gemini_api_key_store.dart';
import '../ai/gemini_operational_intent_resolver.dart';
import '../core/errors/domain_error.dart';
import '../core/id/stable_operation_id.dart';
import '../core/time/business_document_calendar.dart';
import '../database/encrypted_database_opener.dart';
import '../database/spike_database.dart';
import '../finance/local_fx_rate_provider.dart';
import '../operating_engine/pay_supplier_service.dart';
import '../operating_engine/post_expense_service.dart';
import '../operating_engine/post_purchase_return_service.dart';
import '../operating_engine/post_purchase_service.dart';
import '../operating_engine/post_sale_return_service.dart';
import '../operating_engine/post_sale_service.dart';
import '../operating_engine/receive_customer_payment_service.dart';
import '../operating_engine/reverse_expense_service.dart';
import '../operating_engine/transfer_stock_service.dart';
import '../presentation/ai_enabled_persistent_sale_chat_controller.dart';
import '../presentation/persistent_sale_chat_controller.dart';
import '../queries/customer_balance_query.dart';
import '../queries/inventory_query.dart';
import '../queries/local_supplier_lookup.dart';
import '../queries/operational_read_query_service.dart';
import '../queries/supplier_balance_query.dart';
import '../security/authorization_service.dart';
import '../security/secure_database_key_store.dart';
import 'spike_runtime_config.dart';
import 'spike_seed_data.dart';

class IbexRuntimeSession {
  IbexRuntimeSession._({
    required this.db,
    required this.controller,
    required this.databaseFile,
  });

  final SpikeDatabase db;
  final PersistentSaleChatController controller;
  final File databaseFile;

  static Future<IbexRuntimeSession> open({
    SpikeRuntimeConfig config = const SpikeRuntimeConfig(),
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'ibex2-local.db'));
    final key = await SecureDatabaseKeyStore().loadOrCreateHexKey();
    final db = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: file, hexKey: key),
    );

    try {
      if (config.seedDemoData) {
        await SpikeSeedData.ensureSeeded(db, config: config);
      }

      final settings = await (db.select(db.businessSettings)
            ..where((row) => row.businessId.equals(config.businessId)))
          .getSingleOrNull();
      if (settings == null || !settings.onboardingComplete) {
        throw const DomainError(
          'BUSINESS_ONBOARDING_REQUIRED',
          'Local business settings must be completed before operational runtime starts.',
        );
      }
      final baseCurrencyCode = settings.baseCurrencyCode;
      final calendar = FixedOffsetBusinessDocumentCalendar.validated(
        settings.utcOffsetMinutes,
      );

      final catalog = LocalSaleDraftCatalog(
        db: db,
        businessId: config.businessId,
      );
      final createDraft = CreateSaleDraftService(
        catalog: catalog,
        registry: const AgentCommandRegistry({CreateSaleDraftService.commandName}),
      );

      final postSale = PostSaleService(db, calendar: calendar);
      final operationalActions = OperationalActionFacade(
        registry: const AgentCommandRegistry(
          OperationalActionFacade.registeredMutationCommands,
        ),
        authorization: AuthorizationService(db),
        postSale: postSale,
        postPurchase: PostPurchaseService(db),
        receiveCustomerPayment: ReceiveCustomerPaymentService(db),
        paySupplier: PaySupplierService(db),
        transferStock: TransferStockService(db),
        postSaleReturn: PostSaleReturnService(db),
        postPurchaseReturn: PostPurchaseReturnService(db),
        postExpense: PostExpenseService(db),
        reverseExpense: ReverseExpenseService(db),
      );

      final workflow = SaleOperationalWorkflow(
        createSaleDraft: createDraft,
        draftRepository: OperationalDraftRepository(db),
        postSaleService: postSale,
        postSaleExecutor: operationalActions.executePostSale,
      );
      final readQueries = OperationalReadQueryService(
        catalog: catalog,
        customerBalances: CustomerBalanceQuery(db),
        inventory: InventoryQuery(db),
        supplierLookup: LocalSupplierLookup(
          db: db,
          businessId: config.businessId,
        ),
        supplierBalances: SupplierBalanceQuery(db),
        businessId: config.businessId,
        defaultWarehouseId: config.defaultWarehouseId,
      );
      final fx = LocalFxRateProvider(
        db: db,
        businessId: config.businessId,
      );
      final geminiKeyStore = SecureGeminiApiKeyStore();
      final controller = AiEnabledPersistentSaleChatController(
        workflow: workflow,
        readQueries: readQueries,
        defaultWarehouseId: config.defaultWarehouseId,
        aiResolver: GeminiOperationalIntentResolver(keyStore: geminiKeyStore),
        postingContextFactory: (OperationalDraft draft) async {
          final currency = draft.payload['currency_code'];
          if (currency is! String) {
            throw StateError('Approved draft has no currency code.');
          }
          final saleAt = DateTime.now().toUtc();
          final rate = await fx.resolve(
            fromCurrency: currency,
            toCurrency: baseCurrencyCode,
            at: saleAt,
          );
          return SalePostingContext(
            operationId: StableOperationId.forApprovedSaleDraft(
              businessId: config.businessId,
              draftId: draft.draftId,
              version: draft.version,
              fingerprint: draft.fingerprint,
            ),
            businessId: config.businessId,
            userId: config.userId,
            baseCurrencyCode: baseCurrencyCode,
            exchangeRateScaled: rate.rateScaled,
            cashAccountId: config.cashAccountId,
            cashLedgerAccountId: config.cashLedgerAccountId,
            salesRevenueAccountId: config.salesRevenueAccountId,
            inventoryLedgerAccountId: config.inventoryLedgerAccountId,
            cogsLedgerAccountId: config.cogsLedgerAccountId,
            accountsReceivableLedgerAccountId:
                config.accountsReceivableLedgerAccountId,
            saleAt: saleAt,
          );
        },
      );
      await controller.initialize();
      return IbexRuntimeSession._(
        db: db,
        controller: controller,
        databaseFile: file,
      );
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  Future<void> close() async {
    controller.dispose();
    await db.close();
  }
}
