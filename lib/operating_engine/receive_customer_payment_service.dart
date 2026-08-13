import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/domain_error.dart';
import '../core/value_objects/exchange_rate.dart';
import '../core/value_objects/money.dart';
import '../database/spike_database.dart';
import 'document_sequence_service.dart';
import 'receive_customer_payment_command.dart';

class ReceiveCustomerPaymentService {
  ReceiveCustomerPaymentService(this.db, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        _sequence = DocumentSequenceService(db);

  final SpikeDatabase db;
  final Uuid _uuid;
  final DocumentSequenceService _sequence;

  Future<ReceiveCustomerPaymentResult> execute(
    ReceiveCustomerPaymentCommand command,
  ) async {
    if (command.operationId.trim().isEmpty || command.customerId.trim().isEmpty) {
      throw const DomainError('RECEIPT_IDENTITY_REQUIRED', 'Receipt operation and customer are required.');
    }
    if (command.amountScaled <= 0) {
      throw const DomainError('RECEIPT_AMOUNT_INVALID', 'Receipt amount must be greater than zero.');
    }
    if (command.exchangeRateScaled <= 0) {
      throw const DomainError('FX_RATE_INVALID', 'Exchange rate must be positive.');
    }

    final currency = command.currencyCode.trim().toUpperCase();
    final baseCurrency = command.baseCurrencyCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(baseCurrency)) {
      throw const DomainError('RECEIPT_CURRENCY_INVALID', 'Receipt currencies must be ISO-like 3-letter codes.');
    }

    return db.transaction(() async {
      final priorOperation = await (db.select(db.operationLog)
            ..where((row) => row.operationId.equals(command.operationId)))
          .getSingleOrNull();
      if (priorOperation != null) {
        final priorReceipt = await (db.select(db.customerReceipts)
              ..where((row) => row.operationId.equals(command.operationId)))
            .getSingleOrNull();
        if (priorReceipt == null) {
          throw const DomainError(
            'OPERATION_STATE_CORRUPT',
            'Operation exists without its customer receipt result.',
          );
        }
        return ReceiveCustomerPaymentResult(
          receiptId: priorReceipt.id,
          documentNo: priorReceipt.documentNo,
          journalEntryId: priorReceipt.journalEntryId,
          idempotentReplay: true,
        );
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

      final receiptId = _uuid.v4();
      final journalId = _uuid.v4();
      final now = DateTime.now().toUtc();
      final documentNo = await _sequence.nextNumber(
        businessId: command.businessId,
        documentType: 'customer_receipt',
        year: command.receivedAt.toUtc().year,
        prefix: 'RCT',
      );

      await db.into(db.customerReceipts).insert(
            CustomerReceiptsCompanion.insert(
              id: receiptId,
              businessId: command.businessId,
              documentNo: documentNo,
              customerId: command.customerId,
              cashAccountId: command.cashAccountId,
              currencyCode: currency,
              baseCurrencyCode: baseCurrency,
              exchangeRateScaled: command.exchangeRateScaled,
              amountScaled: command.amountScaled,
              baseAmountScaled: baseAmount.scaled,
              journalEntryId: journalId,
              receivedAt: command.receivedAt.toUtc(),
              operationId: command.operationId,
            ),
          );

      await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              id: journalId,
              businessId: command.businessId,
              sourceType: 'customer_receipt',
              sourceId: receiptId,
              status: 'posted',
              entryAt: command.receivedAt.toUtc(),
              operationId: command.operationId,
            ),
          );
      await db.into(db.journalLines).insert(
            JournalLinesCompanion.insert(
              id: _uuid.v4(),
              journalEntryId: journalId,
              accountId: command.cashLedgerAccountId,
              baseDebitScaled: Value(baseAmount.scaled),
              description: const Value('Customer receipt cash'),
            ),
          );
      await db.into(db.journalLines).insert(
            JournalLinesCompanion.insert(
              id: _uuid.v4(),
              journalEntryId: journalId,
              accountId: command.accountsReceivableLedgerAccountId,
              baseCreditScaled: Value(baseAmount.scaled),
              description: const Value('Customer receivable settlement'),
            ),
          );

      await db.into(db.customerLedger).insert(
            CustomerLedgerCompanion.insert(
              id: _uuid.v4(),
              businessId: command.businessId,
              customerId: command.customerId,
              sourceType: 'customer_receipt',
              sourceId: receiptId,
              currencyCode: currency,
              creditScaled: Value(command.amountScaled),
              baseCreditScaled: Value(baseAmount.scaled),
              occurredAt: command.receivedAt.toUtc(),
              operationId: command.operationId,
            ),
          );

      await db.into(db.operationLog).insert(
            OperationLogCompanion.insert(
              operationId: command.operationId,
              businessId: command.businessId,
              commandName: 'ReceiveCustomerPayment',
              entityType: const Value('customer_receipt'),
              entityId: Value(receiptId),
              status: 'committed',
              createdAt: now,
            ),
          );

      await db.into(db.auditLogs).insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              businessId: command.businessId,
              userId: command.userId,
              entityType: 'customer_receipt',
              entityId: receiptId,
              action: 'RECEIVE_CUSTOMER_PAYMENT',
              operationId: command.operationId,
              occurredAt: now,
              metadataJson: jsonEncode({
                'document_no': documentNo,
                'customer_id': command.customerId,
                'amount_scaled': command.amountScaled,
                'currency': currency,
                'base_amount_scaled': baseAmount.scaled,
                'base_currency': baseCurrency,
              }),
            ),
          );

      return ReceiveCustomerPaymentResult(
        receiptId: receiptId,
        documentNo: documentNo,
        journalEntryId: journalId,
        idempotentReplay: false,
      );
    });
  }
}
