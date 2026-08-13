import 'package:drift/drift.dart';

import '../core/numbering/document_number_formatter.dart';
import '../database/spike_database.dart';

class DocumentSequenceService {
  const DocumentSequenceService(this.db);

  final SpikeDatabase db;

  Future<String> nextNumber({
    required String businessId,
    required String documentType,
    required int year,
    required String prefix,
    int padding = 6,
  }) async {
    final scopeKey = year.toString();
    final row = await (db.select(db.documentSequences)
          ..where((t) =>
              t.businessId.equals(businessId) &
              t.documentType.equals(documentType) &
              t.scopeKey.equals(scopeKey)))
        .getSingleOrNull();

    final next = row?.nextValue ?? 1;
    if (row == null) {
      await db.into(db.documentSequences).insert(
            DocumentSequencesCompanion.insert(
              businessId: businessId,
              documentType: documentType,
              scopeKey: scopeKey,
              prefix: prefix,
              nextValue: next + 1,
              padding: Value(padding),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
    } else {
      await (db.update(db.documentSequences)
            ..where((t) =>
                t.businessId.equals(businessId) &
                t.documentType.equals(documentType) &
                t.scopeKey.equals(scopeKey)))
          .write(
        DocumentSequencesCompanion(
          nextValue: Value(next + 1),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }

    return DocumentNumberFormatter.format(
      prefix: prefix,
      year: year,
      sequence: next,
      padding: padding,
    );
  }
}
