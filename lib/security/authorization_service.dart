import 'package:drift/drift.dart';

import '../core/errors/domain_error.dart';
import '../database/spike_database.dart';

class OperationalPermissions {
  const OperationalPermissions._();

  static const postSale = 'sale.post';
  static const postPurchase = 'purchase.post';
  static const receiveCustomerPayment = 'customer_payment.receive';
  static const paySupplier = 'supplier_payment.post';
  static const transferStock = 'stock.transfer';
  static const postSaleReturn = 'sale_return.post';
  static const postPurchaseReturn = 'purchase_return.post';
  static const postExpense = 'expense.post';
  static const reverseExpense = 'expense.reverse';
}

class AuthorizationService {
  const AuthorizationService(this.db);

  final SpikeDatabase db;

  Future<void> requirePermission({
    required String businessId,
    required String userId,
    required String permission,
  }) async {
    final user = await (db.select(db.appUsers)
          ..where((u) =>
              u.id.equals(userId) &
              u.businessId.equals(businessId) &
              u.active.equals(true)))
        .getSingleOrNull();
    if (user == null) {
      throw const DomainError('AUTH_USER_INACTIVE', 'Active local user is required for this operation.');
    }

    final rows = await db.customSelect(
      '''
      SELECT 1
      FROM user_roles ur
      INNER JOIN roles r
        ON r.id = ur.role_id
       AND r.business_id = ur.business_id
       AND r.active = 1
      INNER JOIN role_permissions rp
        ON rp.role_id = ur.role_id
       AND rp.business_id = ur.business_id
      WHERE ur.business_id = ?
        AND ur.user_id = ?
        AND rp.permission = ?
      LIMIT 1
      ''',
      variables: [
        Variable.withString(businessId),
        Variable.withString(userId),
        Variable.withString(permission),
      ],
      readsFrom: {db.userRoles, db.roles, db.rolePermissions},
    ).getSingleOrNull();

    if (rows == null) {
      throw DomainError(
        'AUTH_PERMISSION_DENIED',
        'User does not have required permission: $permission',
      );
    }
  }
}
