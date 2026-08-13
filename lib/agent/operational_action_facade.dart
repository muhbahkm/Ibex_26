import '../operating_engine/pay_supplier_command.dart';
import '../operating_engine/pay_supplier_service.dart';
import '../operating_engine/post_expense_command.dart';
import '../operating_engine/post_expense_service.dart';
import '../operating_engine/post_purchase_command.dart';
import '../operating_engine/post_purchase_return_command.dart';
import '../operating_engine/post_purchase_return_service.dart';
import '../operating_engine/post_purchase_service.dart';
import '../operating_engine/post_sale_command.dart';
import '../operating_engine/post_sale_return_command.dart';
import '../operating_engine/post_sale_return_service.dart';
import '../operating_engine/post_sale_service.dart';
import '../operating_engine/receive_customer_payment_command.dart';
import '../operating_engine/receive_customer_payment_service.dart';
import '../operating_engine/reverse_expense_command.dart';
import '../operating_engine/reverse_expense_service.dart';
import '../operating_engine/transfer_stock_command.dart';
import '../operating_engine/transfer_stock_service.dart';
import '../security/authorization_service.dart';
import 'command_registry.dart';

class OperationalActionFacade {
  const OperationalActionFacade({
    required this.registry,
    required this.authorization,
    required this.postSale,
    required this.postPurchase,
    required this.receiveCustomerPayment,
    required this.paySupplier,
    required this.transferStock,
    required this.postSaleReturn,
    required this.postPurchaseReturn,
    required this.postExpense,
    required this.reverseExpense,
  });

  static const postSaleCommand = 'PostSale';
  static const postPurchaseCommand = 'PostPurchase';
  static const receiveCustomerPaymentCommand = 'ReceiveCustomerPayment';
  static const paySupplierCommand = 'PaySupplier';
  static const transferStockCommand = 'TransferStock';
  static const postSaleReturnCommand = 'PostSaleReturn';
  static const postPurchaseReturnCommand = 'PostPurchaseReturn';
  static const postExpenseCommand = 'PostExpense';
  static const reverseExpenseCommand = 'ReverseExpense';

  static const registeredMutationCommands = {
    postSaleCommand,
    postPurchaseCommand,
    receiveCustomerPaymentCommand,
    paySupplierCommand,
    transferStockCommand,
    postSaleReturnCommand,
    postPurchaseReturnCommand,
    postExpenseCommand,
    reverseExpenseCommand,
  };

  final AgentCommandRegistry registry;
  final AuthorizationService authorization;
  final PostSaleService postSale;
  final PostPurchaseService postPurchase;
  final ReceiveCustomerPaymentService receiveCustomerPayment;
  final PaySupplierService paySupplier;
  final TransferStockService transferStock;
  final PostSaleReturnService postSaleReturn;
  final PostPurchaseReturnService postPurchaseReturn;
  final PostExpenseService postExpense;
  final ReverseExpenseService reverseExpense;

  Future<PostSaleResult> executePostSale(PostSaleCommand command) async {
    registry.requireRegistered(postSaleCommand);
    await authorization.requirePermission(
      businessId: command.businessId,
      userId: command.userId,
      permission: OperationalPermissions.postSale,
    );
    return postSale.execute(command);
  }

  Future<PostPurchaseResult> executePostPurchase(PostPurchaseCommand command) async {
    registry.requireRegistered(postPurchaseCommand);
    await authorization.requirePermission(
      businessId: command.businessId,
      userId: command.userId,
      permission: OperationalPermissions.postPurchase,
    );
    return postPurchase.execute(command);
  }

  Future<ReceiveCustomerPaymentResult> executeReceiveCustomerPayment(
    ReceiveCustomerPaymentCommand command,
  ) async {
    registry.requireRegistered(receiveCustomerPaymentCommand);
    await authorization.requirePermission(
      businessId: command.businessId,
      userId: command.userId,
      permission: OperationalPermissions.receiveCustomerPayment,
    );
    return receiveCustomerPayment.execute(command);
  }

  Future<PaySupplierResult> executePaySupplier(PaySupplierCommand command) async {
    registry.requireRegistered(paySupplierCommand);
    await authorization.requirePermission(
      businessId: command.businessId,
      userId: command.userId,
      permission: OperationalPermissions.paySupplier,
    );
    return paySupplier.execute(command);
  }

  Future<TransferStockResult> executeTransferStock(TransferStockCommand command) async {
    registry.requireRegistered(transferStockCommand);
    await authorization.requirePermission(
      businessId: command.businessId,
      userId: command.userId,
      permission: OperationalPermissions.transferStock,
    );
    return transferStock.execute(command);
  }

  Future<PostSaleReturnResult> executePostSaleReturn(PostSaleReturnCommand command) async {
    registry.requireRegistered(postSaleReturnCommand);
    await authorization.requirePermission(
      businessId: command.businessId,
      userId: command.userId,
      permission: OperationalPermissions.postSaleReturn,
    );
    return postSaleReturn.execute(command);
  }

  Future<PostPurchaseReturnResult> executePostPurchaseReturn(
    PostPurchaseReturnCommand command,
  ) async {
    registry.requireRegistered(postPurchaseReturnCommand);
    await authorization.requirePermission(
      businessId: command.businessId,
      userId: command.userId,
      permission: OperationalPermissions.postPurchaseReturn,
    );
    return postPurchaseReturn.execute(command);
  }

  Future<PostExpenseResult> executePostExpense(PostExpenseCommand command) async {
    registry.requireRegistered(postExpenseCommand);
    await authorization.requirePermission(
      businessId: command.businessId,
      userId: command.userId,
      permission: OperationalPermissions.postExpense,
    );
    return postExpense.execute(command);
  }

  Future<ReverseExpenseResult> executeReverseExpense(ReverseExpenseCommand command) async {
    registry.requireRegistered(reverseExpenseCommand);
    await authorization.requirePermission(
      businessId: command.businessId,
      userId: command.userId,
      permission: OperationalPermissions.reverseExpense,
    );
    return reverseExpense.execute(command);
  }
}
