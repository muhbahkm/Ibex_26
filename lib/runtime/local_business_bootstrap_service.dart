import 'package:drift/drift.dart';

import '../core/errors/domain_error.dart';
import '../core/text/arabic_search_normalizer.dart';
import '../database/spike_database.dart';
import '../security/authorization_service.dart';

class LocalBusinessBootstrapRequest {
  const LocalBusinessBootstrapRequest({
    required this.businessId,
    required this.ownerUserId,
    required this.businessName,
    required this.baseCurrencyCode,
    required this.utcOffsetMinutes,
    required this.defaultWarehouseId,
    required this.defaultWarehouseName,
  });

  final String businessId;
  final String ownerUserId;
  final String businessName;
  final String baseCurrencyCode;
  final int utcOffsetMinutes;
  final String defaultWarehouseId;
  final String defaultWarehouseName;
}

class LocalBusinessBootstrapService {
  const LocalBusinessBootstrapService(this.db);

  final SpikeDatabase db;

  Future<void> execute(LocalBusinessBootstrapRequest request) async {
    final businessName = request.businessName.trim();
    final warehouseName = request.defaultWarehouseName.trim();
    final currency = request.baseCurrencyCode.trim().toUpperCase();
    if (businessName.isEmpty) {
      throw const DomainError('BUSINESS_NAME_REQUIRED', 'Business name is required.');
    }
    if (warehouseName.isEmpty) {
      throw const DomainError('WAREHOUSE_NAME_REQUIRED', 'Default warehouse name is required.');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const DomainError('BASE_CURRENCY_INVALID', 'Base currency must be a three-letter code.');
    }
    if (request.utcOffsetMinutes < -840 || request.utcOffsetMinutes > 840) {
      throw const DomainError(
        'BUSINESS_TIMEZONE_OFFSET_INVALID',
        'Business UTC offset must be within -14:00 and +14:00.',
      );
    }

    final now = DateTime.now().toUtc();
    await db.transaction(() async {
      final existing = await (db.select(db.businessSettings)
            ..where((row) => row.businessId.equals(request.businessId)))
          .getSingleOrNull();
      if (existing?.onboardingComplete == true) {
        throw const DomainError(
          'BUSINESS_ALREADY_BOOTSTRAPPED',
          'Business bootstrap has already been completed.',
        );
      }

      await db.into(db.businessSettings).insertOnConflictUpdate(
            BusinessSettingsCompanion.insert(
              businessId: request.businessId,
              displayName: businessName,
              baseCurrencyCode: currency,
              utcOffsetMinutes: request.utcOffsetMinutes,
              onboardingComplete: const Value(true),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );

      await db.into(db.appUsers).insertOnConflictUpdate(
            AppUsersCompanion.insert(
              id: request.ownerUserId,
              businessId: request.businessId,
              displayName: 'المالك المحلي',
              updatedAt: now,
            ),
          );
      const roleId = 'ROLE-LOCAL-OWNER';
      await db.into(db.roles).insertOnConflictUpdate(
            RolesCompanion.insert(
              id: roleId,
              businessId: request.businessId,
              name: 'مالك الجهاز',
              updatedAt: now,
            ),
          );
      await db.into(db.userRoles).insertOnConflictUpdate(
            UserRolesCompanion.insert(
              businessId: request.businessId,
              userId: request.ownerUserId,
              roleId: roleId,
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
                businessId: request.businessId,
                roleId: roleId,
                permission: permission,
              ),
            );
      }

      await db.into(db.warehouses).insertOnConflictUpdate(
            WarehousesCompanion.insert(
              id: request.defaultWarehouseId,
              businessId: request.businessId,
              name: warehouseName,
              normalizedName: ArabicSearchNormalizer.normalize(warehouseName),
              updatedAt: now,
            ),
          );
    });
  }
}
