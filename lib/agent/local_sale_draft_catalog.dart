import 'package:drift/drift.dart';

import '../core/text/arabic_search_normalizer.dart';
import '../database/spike_database.dart';
import 'create_sale_draft_service.dart';

class LocalSaleDraftCatalog implements SaleDraftCatalog {
  const LocalSaleDraftCatalog({required this.db, required this.businessId});

  final SpikeDatabase db;
  final String businessId;

  @override
  Future<List<SaleDraftCustomer>> findCustomers(String query) async {
    final normalized = ArabicSearchNormalizer.normalize(query);
    if (normalized.isEmpty) return const [];
    final relaxed = _relaxArabicDefiniteArticles(normalized);
    final rows = await db.customSelect(
      '''
      SELECT id, name
      FROM customers
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
      readsFrom: {db.customers},
    ).get();
    return rows
        .map((row) => SaleDraftCustomer(
              id: row.read<String>('id'),
              name: row.read<String>('name'),
            ))
        .toList(growable: false);
  }

  @override
  Future<List<SaleDraftProduct>> findProducts(String query) async {
    final normalized = ArabicSearchNormalizer.normalize(query);
    if (normalized.isEmpty) return const [];
    final relaxed = _relaxArabicDefiniteArticles(normalized);
    final rows = await db.customSelect(
      '''
      SELECT id, name
      FROM products
      WHERE business_id = ? AND active = 1
        AND (
          normalized_name LIKE ? OR normalized_name LIKE ?
          OR UPPER(COALESCE(sku, '')) = UPPER(?)
        )
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
        Variable.withString(query.trim()),
        Variable.withString(normalized),
        Variable.withString(relaxed),
      ],
      readsFrom: {db.products},
    ).get();
    return rows
        .map((row) => SaleDraftProduct(
              id: row.read<String>('id'),
              name: row.read<String>('name'),
            ))
        .toList(growable: false);
  }

  @override
  Future<List<SaleDraftUnit>> findUnitsForProduct(String productId, String query) async {
    final normalized = ArabicSearchNormalizer.normalize(query);
    if (normalized.isEmpty) return const [];
    final relaxed = _relaxArabicDefiniteArticles(normalized);
    final rows = await db.customSelect(
      '''
      SELECT u.id, u.name, u.quantity_precision
      FROM units u
      INNER JOIN product_units pu ON pu.unit_id = u.id
      WHERE pu.product_id = ?
        AND (u.normalized_name LIKE ? OR u.normalized_name LIKE ?)
      ORDER BY CASE
        WHEN u.normalized_name = ? THEN 0
        WHEN u.normalized_name = ? THEN 1
        ELSE 2
      END, pu.is_base DESC, u.name
      LIMIT 8
      ''',
      variables: [
        Variable.withString(productId),
        Variable.withString('%$normalized%'),
        Variable.withString('%$relaxed%'),
        Variable.withString(normalized),
        Variable.withString(relaxed),
      ],
      readsFrom: {db.units, db.productUnits},
    ).get();
    return rows
        .map((row) => SaleDraftUnit(
              id: row.read<String>('id'),
              name: row.read<String>('name'),
              quantityPrecision: row.read<int>('quantity_precision'),
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
