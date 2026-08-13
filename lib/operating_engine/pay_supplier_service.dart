import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/domain_error.dart';
import '../core/value_objects/exchange_rate.dart';
import '../core/value_objects/money.dart';
import '../database/spike_database.dart';
import 'document_sequence_service.dart';
import 'pay_supplier_command.dart';

class PaySupplierService {
  PaySupplierService(this.db, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        _sequence = DocumentSequenceService(db);

  final SpikeDatabase db;
  final Uuid _uuid;
  final DocumentSequenceService _sequence;

  Future<PaySupplierResult> execute(PaySupplierCommand command) async {
    if (command.operationId.trim().isEmpty || command.supplierId.trim().isEmpty) {
      throw const DomainError('SUPPLIER_PAYMENT_IDENTITY_REQUIRED', 'Supplier payment operation and supplier are required.');
    }
    if (command.amountScaled <= 0) {
      throw const DomainError('SUPPLIER_PAYMENT_AMOUNT_INVALID', 'Supplier payment amount must be greater than zero.');
    }
    if (command.exchangeRateScaled <= 0) {
      throw const DomainError('FX_RATE_INVALID', 'Exchange rate must be positive.');
    }
    final currency = command.currencyCode.trim().toUpperCase();
    final baseCurrency = command.baseCurrencyCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(baseCurrency)) {
      throw const DomainError('SUPPLIER_PAYMENT_CURRENCY_INVALID', 'Supplier payment currencies must be ISO-like 3-letter codes.');
    }

    return db.transaction(() async {
      final prior = await (db.select(db.operationLog)
            ..where((row) => row.operationId.equals(command.operationId)))
          .getSingleOrNull();
      if (prior != null) {
        final payment = await (db.select(db.supplierPayments)
              ..where((row) => row.operationId.equals(command.operationId)))
            .getSingleOrNull();
        if (payment == null) {
          throw const DomainError('OPERATION_STATE_CORRUPT', 'Operation exists without supplier payment truth.');
        }
        return PaySupplierResult(
          paymentId: payment.id,
          documentNo: payment.documentNo,
          journalEntryId: payment.journalEntryId,
          idempotentReplay: true,
        );
      }

      final supplier = await (db.select(db.suppliers)
            ..where((row) =>
                row.id.equals(command.supplierId) &
                row.businessId.equals(command.businessId) &
                row.active.equals(true)))
          .getSingleOrNull();
      if (supplier == null) {
        throw const DomainError('SUPPLIER_NOT_FOUND', 'Supplier is not active in this business.');
      }

      final amount = Money.fromScaled(command.amountScaled, currency);
      final rate = ExchangeRate.fromScaled(
        scaled: command.exchangeRateScaled,
        fromCurrency: currency,
        toCurrency: baseCurrency,
      );
      final baseAmount = currency == baseCurrency
          ? Money.fromScaled(command.amountScaled, baseCurrency)
          : rate.convert(amount);

      final paymentId = _uuid.v4();
      final journalId = _uuid.v4();
      final now = DateTime.now().toUtc();
      final documentNo = await _sequence.nextNumber(
        businessId: command.businessId,
        documentType: 'supplier_payment',
        year: command.paidAt.toUtc().year,
        prefix: 'PAY',
      );

      await db.into(db.supplierPayments).insert(
            SupplierPaymentsCompanion.insert(
              id: paymentId,
              businessId: command.businessId,
              documentNo: documentNo,
              supplierId: command.supplierId,
              cashAccountId: command.cashAccountId,
              currencyCode: currency,
              baseCurrencyCode: baseCurrency,
              exchangeRateScaled: command.exchangeRateScaled,
              amountScaled: command.amountScaled,
              baseAmountScaled: baseAmount.scaled,
              journalEntryId: journalId,
              paidAt: command.paidAt.toUtc(),
              operationId: command.operationId,
            ),
          );

      await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              id: journalId,
              businessId: command.businessId,
              sourceType: 'supplier_payment',
              sourceId: paymentId,
              status: 'posted',
              entryAt: command.paidAt.toUtc(),
              operationId: command.operationId,
            ),
          );
      await db.into(db.journalLines).insert(
            JournalLinesCompanion.insert(
              id: _uuid.v4(),
              journalEntryId: journalId,
              accountId: command.accountsPayableLedgerAccountId,
              baseDebitScaled: Value(baseAmount.scaled),
              description: const Value('Supplier payable settlement'),
            ),
          );
      await db.into(db.journalLines).insert(
            JournalLinesCompanion.insert(
              id: _uuid.v4(),
              journalEntryId: journalId,
              accountId: command.cashLedgerAccountId,
              baseCreditScaled: Value(baseAmount.scaled),
              description: const Value('Supplier payment cash'),
            ),
          );

      await db.into(db.supplierLedger).insert(
            SupplierLedgerCompanion.insert(
              id: _uuid.v4(),
              businessId: command.businessId,
              supplierId: command.supplierId,
              sourceType: 'supplier_payment',
              sourceId: paymentId,
              currencyCode: currency,
              debitScaled: Value(command.amountScaled),
              baseDebitScaled: Value(baseAmount.scaled),
              occurredAt: command.paidAt.toUtc(),
              operationId: command.operationId,
            ),
          );

      await db.into(db.operationLog).insert(
            OperationLogCompanion.insert(
              operationId: command.operationId,
              businessId: command.businessId,
              commandName: 'PaySupplier',
              entityType: const Value('supplier_payment'),
              entityId: Value(paymentId),
              status: 'committed',
              createdAt: now,
            ),
          );

      await db.into(db.auditLogs).insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              businessId: command.businessId,
              userId: command.userId,
              entityType: 'supplier_payment',
              entityId: paymentId,
              action: 'PAY_SUPPLIER',
              operationId: command.operationId,
              occurredAt: now,
              metadataJson: jsonEncode({
                'document_no': documentNo,
                'supplier_id': command.supplierId,
                'amount_scaled': command.amountScaled,
                'currency': currency,
                'base_amount_scaled': baseAmount.scaled,
                'base_currency': baseCurrency,
              }),
            ),
          );

      return PaySupplierResult(
        paymentId: paymentId,
        documentNo: documentNo,
        journalEntryId: journalId,
        idempotentReplay: false,
      );
    });
  }
}
