import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/errors/domain_error.dart';
import '../database/spike_database.dart';
import 'document_sequence_service.dart';
import 'reverse_expense_command.dart';

class ReverseExpenseService {
  ReverseExpenseService(this.db, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        _sequence = DocumentSequenceService(db);

  final SpikeDatabase db;
  final Uuid _uuid;
  final DocumentSequenceService _sequence;

  Future<ReverseExpenseResult> execute(ReverseExpenseCommand command) async {
    if (command.operationId.trim().isEmpty ||
        command.businessId.trim().isEmpty ||
        command.userId.trim().isEmpty ||
        command.sourceExpenseId.trim().isEmpty) {
      throw const DomainError(
        'EXPENSE_REVERSAL_IDENTITY_REQUIRED',
        'Reversal operation, business, user and source expense are required.',
      );
    }
    final reason = command.reason.trim();
    if (reason.isEmpty) {
      throw const DomainError(
        'EXPENSE_REVERSAL_REASON_REQUIRED',
        'A reversal reason is required.',
      );
    }

    return db.transaction(() async {
      final priorOperation = await (db.select(db.operationLog)
            ..where((row) => row.operationId.equals(command.operationId)))
          .getSingleOrNull();
      if (priorOperation != null) {
        final prior = await (db.select(db.expenseReversals)
              ..where((row) => row.operationId.equals(command.operationId)))
            .getSingleOrNull();
        if (prior == null) {
          throw const DomainError(
            'OPERATION_STATE_CORRUPT',
            'Operation exists without its canonical expense reversal result.',
          );
        }
        return ReverseExpenseResult(
          expenseReversalId: prior.id,
          documentNo: prior.documentNo,
          journalEntryId: prior.journalEntryId,
          idempotentReplay: true,
        );
      }

      final source = await (db.select(db.expenses)
            ..where((row) =>
                row.id.equals(command.sourceExpenseId) &
                row.businessId.equals(command.businessId)))
          .getSingleOrNull();
      if (source == null) {
        throw const DomainError(
          'SOURCE_EXPENSE_NOT_FOUND',
          'Posted source expense was not found in this business.',
        );
      }
      if (source.status != 'posted') {
        throw const DomainError(
          'EXPENSE_NOT_REVERSIBLE',
          'Only a posted, unreversed expense can be reversed.',
        );
      }

      final sourceJournal = await (db.select(db.journalEntries)
            ..where((row) =>
                row.id.equals(source.journalEntryId) &
                row.businessId.equals(command.businessId) &
                row.status.equals('posted')))
          .getSingleOrNull();
      if (sourceJournal == null ||
          sourceJournal.sourceType != 'expense' ||
          sourceJournal.sourceId != source.id) {
        throw const DomainError(
          'EXPENSE_SOURCE_JOURNAL_INVALID',
          'Source expense journal is missing or inconsistent.',
        );
      }

      final sourceLines = await (db.select(db.journalLines)
            ..where((row) => row.journalEntryId.equals(sourceJournal.id)))
          .get();
      if (sourceLines.isEmpty) {
        throw const DomainError(
          'EXPENSE_SOURCE_JOURNAL_INVALID',
          'Source expense journal has no lines.',
        );
      }
      final debitTotal = sourceLines.fold<int>(
        0,
        (sum, line) => sum + line.baseDebitScaled,
      );
      final creditTotal = sourceLines.fold<int>(
        0,
        (sum, line) => sum + line.baseCreditScaled,
      );
      if (debitTotal <= 0 || debitTotal != creditTotal) {
        throw const DomainError(
          'EXPENSE_SOURCE_JOURNAL_UNBALANCED',
          'Source expense journal must be balanced before reversal.',
        );
      }

      final reversalId = _uuid.v4();
      final journalId = _uuid.v4();
      final now = DateTime.now().toUtc();
      final documentNo = await _sequence.nextNumber(
        businessId: command.businessId,
        documentType: 'expense_reversal',
        year: command.reversedAt.toUtc().year,
        prefix: 'EXR',
      );

      await db.into(db.expenseReversals).insert(
            ExpenseReversalsCompanion.insert(
              id: reversalId,
              businessId: command.businessId,
              documentNo: documentNo,
              sourceExpenseId: source.id,
              reason: reason,
              journalEntryId: journalId,
              reversedAt: command.reversedAt.toUtc(),
              operationId: command.operationId,
            ),
          );
      await db.into(db.journalEntries).insert(
            JournalEntriesCompanion.insert(
              id: journalId,
              businessId: command.businessId,
              sourceType: 'expense_reversal',
              sourceId: reversalId,
              status: 'posted',
              entryAt: command.reversedAt.toUtc(),
              operationId: command.operationId,
            ),
          );
      for (final sourceLine in sourceLines) {
        await db.into(db.journalLines).insert(
              JournalLinesCompanion.insert(
                id: _uuid.v4(),
                journalEntryId: journalId,
                accountId: sourceLine.accountId,
                baseDebitScaled: Value(sourceLine.baseCreditScaled),
                baseCreditScaled: Value(sourceLine.baseDebitScaled),
                description: Value(
                  sourceLine.description == null
                      ? 'Expense reversal'
                      : 'Reversal: ${sourceLine.description}',
                ),
              ),
            );
      }

      final changed = await (db.update(db.expenses)
            ..where((row) =>
                row.id.equals(source.id) &
                row.businessId.equals(command.businessId) &
                row.status.equals('posted')))
          .write(const ExpensesCompanion(status: Value('reversed')));
      if (changed != 1) {
        throw const DomainError(
          'EXPENSE_REVERSAL_CONFLICT',
          'Expense lifecycle changed before reversal could commit.',
        );
      }

      await db.into(db.operationLog).insert(
            OperationLogCompanion.insert(
              operationId: command.operationId,
              businessId: command.businessId,
              commandName: 'ReverseExpense',
              entityType: const Value('expense_reversal'),
              entityId: Value(reversalId),
              status: 'committed',
              createdAt: now,
            ),
          );
      await db.into(db.auditLogs).insert(
            AuditLogsCompanion.insert(
              id: _uuid.v4(),
              businessId: command.businessId,
              userId: command.userId,
              entityType: 'expense_reversal',
              entityId: reversalId,
              action: 'REVERSE_EXPENSE',
              operationId: command.operationId,
              occurredAt: now,
              metadataJson: jsonEncode({
                'document_no': documentNo,
                'source_expense_id': source.id,
                'source_document_no': source.documentNo,
                'reason': reason,
                'base_amount_scaled': source.baseAmountScaled,
              }),
            ),
          );

      return ReverseExpenseResult(
        expenseReversalId: reversalId,
        documentNo: documentNo,
        journalEntryId: journalId,
        idempotentReplay: false,
      );
    });
  }
}
