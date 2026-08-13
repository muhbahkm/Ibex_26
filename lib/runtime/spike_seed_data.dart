import 'package:drift/drift.dart';

import '../core/text/arabic_search_normalizer.dart';
import '../database/spike_database.dart';
import '../security/authorization_service.dart';
import 'spike_runtime_config.dart';

class SpikeSeedData {
  const SpikeSeedData._();

  static Future<void> ensureSeeded(
    SpikeDatabase db, {
    SpikeRuntimeConfig config = const SpikeRuntimeConfig(),
  }) async {
    final now = DateTime.now().toUtc();
    final fxEffectiveAt = DateTime.utc(2026, 1, 1);
    await db.transaction(() async {
      await db.into(db.businessSettings).insertOnConflictUpdate(
            BusinessSettingsCompanion.insert(
              businessId: config.businessId,
              displayName: 'IBEX Local Demo',
              baseCurrencyCode: config.baseCurrencyCode,
              utcOffsetMinutes: 180,
              onboardingComplete: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.into(db.warehouses).insertOnConflictUpdate(
            WarehousesCompanion.insert(
              id: config.defaultWarehouseId,
              businessId: config.businessId,
              name: 'المستودع الرئيسي',
              normalizedName: ArabicSearchNormalizer.normalize('المستودع الرئيسي'),
              updatedAt: now,
            ),
          );
      await db.into(db.warehouses).insertOnConflictUpdate(
            WarehousesCompanion.insert(
              id: 'WH-SECONDARY',
              businessId: config.businessId,
              name: 'المستودع الفرعي',
              normalizedName: ArabicSearchNormalizer.normalize('المستودع الفرعي'),
              updatedAt: now,
            ),
          );

      // IBEX is local-first: the installation is immediately usable without
      // cloud authentication. This record is an internal audit/authorization
      // identity for the device owner, not a login account.
      await db.into(db.appUsers).insertOnConflictUpdate(
            AppUsersCompanion.insert(
              id: config.userId,
              businessId: config.businessId,
              displayName: 'المالك المحلي',
              updatedAt: now,
            ),
          );
      await db.into(db.roles).insertOnConflictUpdate(
            RolesCompanion.insert(
              id: 'ROLE-LOCAL-ADMIN',
              businessId: config.businessId,
              name: 'مالك الجهاز',
              updatedAt: now,
            ),
          );
      await db.into(db.userRoles).insertOnConflictUpdate(
            UserRolesCompanion.insert(
              businessId: config.businessId,
              userId: config.userId,
              roleId: 'ROLE-LOCAL-ADMIN',
            ),
          );
      for (final permission in const [
        OperationalPermissions.postSale,
        OperationalPermissions.postPurchase,
        OperationalPermissions.receiveCustomerPayment,
        OperationalPermissions.paySupplier,
        OperationalPermissions.transferStock,
        OperationalPermissions.postSaleReturn,
        OperationalPermissions.postPurchaseReturn,
        OperationalPermissions.postExpense,
        OperationalPermissions.reverseExpense,
      ]) {
        await db.into(db.rolePermissions).insertOnConflictUpdate(
              RolePermissionsCompanion.insert(
                businessId: config.businessId,
                roleId: 'ROLE-LOCAL-ADMIN',
                permission: permission,
              ),
            );
      }

      await db.into(db.customers).insertOnConflictUpdate(
            CustomersCompanion.insert(
              id: 'CUSTOMER-GENERAL',
              businessId: config.businessId,
              name: 'زبون عام',
              normalizedName: ArabicSearchNormalizer.normalize('زبون عام'),
              updatedAt: now,
            ),
          );
      await db.into(db.customers).insertOnConflictUpdate(
            CustomersCompanion.insert(
              id: 'CUSTOMER-MOHAMMED-BAHAKAM',
              businessId: config.businessId,
              name: 'محمد عبدالله باحكم',
              normalizedName: ArabicSearchNormalizer.normalize('محمد عبدالله باحكم'),
              updatedAt: now,
            ),
          );
      await db.into(db.suppliers).insertOnConflictUpdate(
            SuppliersCompanion.insert(
              id: 'SUPPLIER-HONEY-DEMO',
              businessId: config.businessId,
              name: 'مورد العسل',
              normalizedName: ArabicSearchNormalizer.normalize('مورد العسل'),
              updatedAt: now,
            ),
          );

      await db.into(db.products).insertOnConflictUpdate(
            ProductsCompanion.insert(
              id: 'PRODUCT-SIDR-1KG',
              businessId: config.businessId,
              sku: const Value('SIDR-1KG'),
              name: 'سدر — عبوة كيلو',
              normalizedName: ArabicSearchNormalizer.normalize('سدر عبوة كيلو'),
              updatedAt: now,
            ),
          );
      await db.into(db.units).insertOnConflictUpdate(
            UnitsCompanion.insert(
              id: 'UNIT-GALLON',
              name: 'جالون',
              normalizedName: ArabicSearchNormalizer.normalize('جالون'),
              quantityPrecision: 0,
            ),
          );
      await db.into(db.productUnits).insertOnConflictUpdate(
            const ProductUnitsCompanion(
              productId: Value('PRODUCT-SIDR-1KG'),
              unitId: Value('UNIT-GALLON'),
              conversionFactorScaled: Value(1000000),
              isBase: Value(true),
            ),
          );

      for (final rate in [
        (id: 'FX-SAR-YER-DEMO', from: 'SAR', scaled: 425 * 100000000),
        (id: 'FX-USD-YER-DEMO', from: 'USD', scaled: 1600 * 100000000),
      ]) {
        await db.into(db.fxRates).insertOnConflictUpdate(
              FxRatesCompanion.insert(
                id: rate.id,
                businessId: config.businessId,
                fromCurrency: rate.from,
                toCurrency: config.baseCurrencyCode,
                rateScaled: rate.scaled,
                effectiveAt: fxEffectiveAt,
                sourceNote: const Value('Disposable spike seed; replace with user-configured business rate before production.'),
                createdAt: now,
              ),
            );
      }

      final balance = await (db.select(db.inventoryBalances)
            ..where((row) =>
                row.warehouseId.equals(config.defaultWarehouseId) &
                row.productId.equals('PRODUCT-SIDR-1KG')))
          .getSingleOrNull();
      if (balance == null) {
        await db.into(db.inventoryBalances).insert(
              InventoryBalancesCompanion.insert(
                warehouseId: config.defaultWarehouseId,
                productId: 'PRODUCT-SIDR-1KG',
                quantityScaled: 100 * 1000000,
                inventoryValueScaled: 250000 * 10000,
                wacUnitCostScaled: 2500 * 10000,
                updatedAt: now,
              ),
            );
      }
    });
  }
}
