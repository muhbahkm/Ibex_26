import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/local_sale_draft_catalog.dart';
import 'package:ibex_foundation_spike/core/text/arabic_search_normalizer.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';

void main() {
  late SpikeDatabase db;
  late LocalSaleDraftCatalog catalog;

  setUp(() async {
    db = SpikeDatabase.inMemory();
    catalog = LocalSaleDraftCatalog(db: db, businessId: 'B-1');
    final now = DateTime.utc(2026, 8, 11);

    await db.into(db.customers).insert(
          CustomersCompanion.insert(
            id: 'C-1',
            businessId: 'B-1',
            name: 'محمد عبدالله باحكم',
            normalizedName: ArabicSearchNormalizer.normalize('محمد عبدالله باحكم'),
            updatedAt: now,
          ),
        );
    await db.into(db.customers).insert(
          CustomersCompanion.insert(
            id: 'C-OTHER',
            businessId: 'B-2',
            name: 'محمد عبدالله باحكم',
            normalizedName: ArabicSearchNormalizer.normalize('محمد عبدالله باحكم'),
            updatedAt: now,
          ),
        );
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: 'P-1',
            businessId: 'B-1',
            sku: const Value('SIDR-1KG'),
            name: 'سدر — عبوة كيلو',
            normalizedName: ArabicSearchNormalizer.normalize('سدر عبوة كيلو'),
            updatedAt: now,
          ),
        );
    await db.into(db.units).insert(
          UnitsCompanion.insert(
            id: 'U-1',
            name: 'جالون',
            normalizedName: ArabicSearchNormalizer.normalize('جالون'),
            quantityPrecision: 0,
          ),
        );
    await db.into(db.productUnits).insert(
          const ProductUnitsCompanion(
            productId: Value('P-1'),
            unitId: Value('U-1'),
            conversionFactorScaled: Value(1000000),
            isBase: Value(true),
          ),
        );
  });

  tearDown(() => db.close());

  test('Arabic normalization tolerates hamza diacritics and punctuation', () {
    expect(
      ArabicSearchNormalizer.normalize('  مُحَمَّد، عبدُالله '),
      'محمد عبدالله',
    );
    expect(ArabicSearchNormalizer.normalize('إبراهيم'), 'ابراهيم');
  });

  test('customer resolution is business scoped and searchable by normalized Arabic', () async {
    final matches = await catalog.findCustomers('محمد عبدالله');
    expect(matches, hasLength(1));
    expect(matches.single.id, 'C-1');
  });

  test('product resolves by Arabic name or exact SKU', () async {
    final byName = await catalog.findProducts('سدر عبوة');
    expect(byName.single.id, 'P-1');

    final byArticleName = await catalog.findProducts('السدر عبوة كيلو');
    expect(byArticleName.single.id, 'P-1');

    final bySku = await catalog.findProducts('SIDR-1KG');
    expect(bySku.single.id, 'P-1');
  });

  test('unit resolution tolerates the Arabic definite article and stays product scoped', () async {
    final units = await catalog.findUnitsForProduct('P-1', 'الجالون');
    expect(units, hasLength(1));
    expect(units.single.quantityPrecision, 0);

    final none = await catalog.findUnitsForProduct('P-UNKNOWN', 'جالون');
    expect(none, isEmpty);
  });
}
