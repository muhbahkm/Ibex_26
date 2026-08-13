import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/domain_error.dart';
import '../core/value_objects/exchange_rate.dart';
import '../core/value_objects/money.dart';
import '../database/spike_database.dart';
import 'document_sequence_service.dart';
import 'post_expense_command.dart';

class PostExpenseService {
  PostExpenseService(this.db, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        _sequence = DocumentSequenceService(db);

  final SpikeDatabase db;
  final Uuid _uuid;
  final DocumentSequenceService _sequence;

  Future<PostExpenseResult> execute(PostExpenseCommand command) async {
    if (command.operationId.trim().isEmpty ||
        command.businessId.trim().isEmpty ||
        command.userId.trim().isEmpty ||
        command.category.trim().isEmpty) {
      throw const DomainError(
        'EXPENSE_IDENTITY_REQUIRED',
        'Expense operation, business, user and category are required.',
      );
    }
    if (command.amountScaled <= 0) {
      throw const DomainError(
        'EXPENSE_AMOUNT_INVALID',
        'Expense amount must be greater than zero.',
      );
    }
    if (command.exchangeRateScaled <= 0) {
      throw const DomainError('FX_RATE_INVALID', 'Exchange rate must be positive.');
    }
    if (command.cashAccountId.trim().isEmpty ||
        command.cashLedgerAccountId.trim().isEmpty ||
        command.expenseLedgerAccountId.trim().isEmpty) {
      throw const DomainError(
        'EXPENSE_ACCOUNTS_REQUIRED',
        'Expense cash and ledger accounts are required.',
      );
    }

    final currency = command.currencyCode.trim().toUpperCase();
    final baseCurrency = command.baseCurrencyCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(baseCurrency)) {
      throw const DomainError(
        'EXPENSE_CURRENCY_INVALID',
        'Expense currencies must be ISO-like 3-letter codes.',
      );
    }
    if (currency == baseCurrency && command.exchangeRateScaled != 100000000) {
      throw const DomainError(
        'FX_BASE_RATE_INVALID',
        'Base-currency expense must use an exact 1e8 exchange rate.',
      );
    }

    return db.transaction(() async {
      final priorOperation = await (db.select(db.operationLog)
            ..where((row) => row.operationId.equals(command.operationId)))
          .getSingleOrNull();
      if (priorOperation != null) {
        final prior = await (db.select(db.expenses)
              ..where((row) => row.operationId.equals(command.operationId)))
            .getSingleOrNull();
        if (prior == null) {
          throw const DomainError(
            'OPERATION_STATE_CORRUPT',
            'Operation exists without its canonical expense result.',
          );
        }
        return PostExpenseResult(
          expenseId: prior.id,
          documentNo: prior.documentNo,
          journalEntryId: prior.journalEntryId,
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

      final expenseId = _uuid.v4();
      final journalId = _uuid.v4();
      final now = DateTime.now().toUtc();
      final documentNo = await _sequence.nextNumber(
        businessId: command.businessId,
        documentType: 'expense',
        year: command.expenseAt.toUtc().year,
        prefix: 'EXP',
      );

      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              id: expenseId,
              businessId: command.businessId,
              documentNo: documentNo,
              category: command.category.trim(),
              description: Value(command.description?.trim()),
              cashAccountId: command.cashAccountId,
              currencyCode: currency,
              baseCurrencyCode: baseCurrency,
              exchangeRateScaled: command.exchangeRateScaled,
              amountScaled: command.amountScaled,
              baseAmountScaled: baseAmount.scaled,
              journalEntryId: journalId,
              expenseAt: command.expenseAt.toUtc(),
              operationId: command.operationId,
            ),
          );

      await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              id: journalId,
              businessId: command.businessId,
              sourceType: 'expense',
              sourceId: expenseId,
              status: 'posted',
              entryAt: command.expenseAt.toUtc(),
              operationId: command.operationId,
            ),
          );
      await db.into(db.journalLines).insert(
            JournalLinesCompanion.insert(
              id: _uuid.v4(),
              journalEntryId: journalId,
              accountId: command.expenseLedgerAccountId,
              baseDebitScaled: Value(baseAmount.scaled),
              description: Value(command.category.trim()),
            ),
          );
      await db.into(db.journalLines).insert(
            JournalLinesCompanion.insert(
              id: _uuid.v4(),
              journalEntryId: journalId,
              accountId: command.cashLedgerAccountId,
              baseCreditScaled: Value(baseAmount.scaled),
              description: const Value('Expense cash outflow'),
            ),
          );

      await db.into(db.operationLog).insert(
            OperationLogCompanion.insert(
              operationId: command.operationId,
              businessId: command.businessId,
              commandName: 'PostExpense',
              entityType: const Value('expense'),
              entityId: Value(expenseId),
              status: 'committed',
              createdAt: now,
            ),
          );
      await db.into(db.auditLogs).insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              businessId: command.businessId,
              userId: command.userId,
              entityType: 'expense',
              entityId: expenseId,
              action: 'POST_EXPENSE',
              operationId: command.operationId,
              occurredAt: now,
              metadataJson: jsonEncode({
                'document_no': documentNo,
                'category': command.category.trim(),
                'amount_scaled': command.amountScaled,
                'currency': currency,
                'base_amount_scaled': baseAmount.scaled,
                'base_currency': baseCurrency,
                'cash_account_id': command.cashAccountId,
              }),
            ),
          );

      return PostExpenseResult(
        expenseId: expenseId,
        documentNo: documentNo,
        journalEntryId: journalId,
        idempotentReplay: false,
      );
    });
  }
}
