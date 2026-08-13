import 'package:drift/drift.dart';

import '../core/text/arabic_search_normalizer.dart';
import '../database/spike_database.dart';

class SupplierLookupResult {
  const SupplierLookupResult({required this.id, required this.name});
  final String id;
  final String name;
}

class LocalSupplierLookup {
  const LocalSupplierLookup({required this.db, required this.businessId});

  final SpikeDatabase db;
  final String businessId;

  Future<List<SupplierLookupResult>> find(String query) async {
    final normalized = ArabicSearchNormalizer.normalize(query);
    if (normalized.isEmpty) return const [];
    final relaxed = _relaxArabicDefiniteArticles(normalized);
    final rows = await db.customSelect(
      '''
      SELECT id, name
      FROM suppliers
      WHERE business_id = ? AND active = 1
        AND (normalized_name LIKE ? OR normalized_name LIKE ?)
      ORDER BY CASE
        WHEN normalized_name = ? THEN 0
        WHEN normalized_name = ? THEN 1
        ELSE 2
      END, name
      LIMIT 8
      ''',
      variables: [
        Variable.withString(businessId),
        Variable.withString('%$normalized%'),
        Variable.withString('%$relaxed%'),
        Variable.withString(normalized),
        Variable.withString(relaxed),
      ],
      readsFrom: {db.suppliers},
    ).get();
    return rows
        .map((row) => SupplierLookupResult(
              id: row.read<String>('id'),
              name: row.read<String>('name'),
            ))
        .toList(growable: false);
  }

  String _relaxArabicDefiniteArticles(String normalized) {
    return normalized
        .split(' ')
        .map((token) => token.startsWith('ال') && token.length > 3
            ? token.substring(2)
            : token)
        .join(' ');
  }
}
