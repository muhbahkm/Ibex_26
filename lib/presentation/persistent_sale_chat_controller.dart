import 'dart:async';

import '../agent/create_sale_draft_service.dart';
import '../agent/operational_draft.dart';
import '../agent/sale_intent_interpreter.dart';
import '../agent/sale_operational_workflow.dart';
import '../core/errors/domain_error.dart';
import '../queries/operational_read_intent_interpreter.dart';
import '../queries/operational_read_query_service.dart';
import 'sale_chat_controller.dart';

class PersistentSaleChatController extends SaleChatController {
  PersistentSaleChatController({
    required this.workflow,
    required this.postingContextFactory,
    this.defaultWarehouseId = 'WH-1',
    this.readQueries,
    SaleIntentInterpreter interpreter = const SaleIntentInterpreter(),
    OperationalReadIntentInterpreter readInterpreter =
        const OperationalReadIntentInterpreter(),
  })  : _interpreter = interpreter,
        _readInterpreter = readInterpreter,
        super(
          createSaleDraft: workflow.createSaleDraft,
          workflow: workflow,
          postingContextFactory: postingContextFactory,
          defaultWarehouseId: defaultWarehouseId,
        );

  final SaleOperationalWorkflow workflow;
  final SalePostingContextFactory postingContextFactory;
  final String defaultWarehouseId;
  final OperationalReadQueryService? readQueries;
  final SaleIntentInterpreter _interpreter;
  final OperationalReadIntentInterpreter _readInterpreter;

  OperationalDraft? _runtimeDraft;
  bool _runtimeBusy = false;
  String? _runtimeError;
  final List<SaleChatMessage> _runtimeMessages = [];

  @override
  bool get persistent => true;

  @override
  bool get busy => _runtimeBusy;

  @override
  String? get lastError => _runtimeError;

  @override
  OperationalDraft? get draft => _runtimeDraft;

  @override
  List<SaleChatMessage> get messages => List.unmodifiable(_runtimeMessages);

  @override
  Future<void> initialize() async {
    if (_runtimeBusy) return;
    _runtimeBusy = true;
    _runtimeError = null;
    notifyListeners();
    try {
      _runtimeDraft = await workflow.loadLatestOpen();
      if (_runtimeDraft != null) {
        _runtimeMessages.add(
          SaleChatMessage(
            role: 'assistant',
            text: 'استعدت مسودة البيع المفتوحة رقم الإصدار ${_runtimeDraft!.version}. راجعها قبل المتابعة.',
          ),
        );
      }
    } on DomainError catch (error) {
      _runtimeError = error.code;
    } finally {
      _runtimeBusy = false;
      notifyListeners();
    }
  }

  @override
  Future<void> initializeDemoDraft() => initialize();

  @override
  void approve() => unawaited(_runOperation(() async {
        final current = _requireDraft();
        _runtimeDraft = await workflow.approve(current.draftId);
        _runtimeMessages.add(
          const SaleChatMessage(
            role: 'assistant',
            text: 'تمت الموافقة على النسخة الحالية. لم يتم الترحيل بعد؛ اكتب «رحّل الفاتورة» للتنفيذ النهائي.',
          ),
        );
      }));

  @override
  void cancel() => unawaited(_runOperation(() async {
        final current = _requireDraft();
        _runtimeDraft = await workflow.cancel(current.draftId);
        _runtimeMessages.add(
          const SaleChatMessage(
            role: 'assistant',
            text: 'ألغيت المسودة دون إنشاء قيد أو حركة مخزون.',
          ),
        );
      }));

  @override
  void requestEditTo400() => revisePrice('400');

  @override
  void revisePrice(String priceText) => unawaited(_runOperation(() async {
        final current = _requireDraft();
        _runtimeDraft = await workflow.revisePrice(current.draftId, priceText);
        _runtimeMessages.add(
          SaleChatMessage(
            role: 'assistant',
            text: 'تم تعديل السعر إلى $priceText ${viewData?.currencyCode ?? ''}. أُلغيت الموافقة السابقة وتحتاج النسخة الجديدة إلى مراجعة.',
          ),
        );
      }));

  @override
  void submitNaturalLanguage(String text) {
    final value = text.trim();
    if (value.isEmpty || _runtimeBusy) return;
    _runtimeMessages.add(SaleChatMessage(role: 'user', text: value));
    notifyListeners();

    final readIntent = _readInterpreter.interpret(value);
    if (readIntent is! UnsupportedOperationalReadIntent && readQueries != null) {
      unawaited(_executeReadIntent(readIntent));
      return;
    }
    unawaited(_executeSaleIntent(value));
  }

  Future<void> _executeReadIntent(OperationalReadIntent intent) async {
    await _runOperation(() async {
      final queries = readQueries;
      if (queries == null) {
        throw const DomainError(
          'READ_QUERY_SERVICE_UNAVAILABLE',
          'Local operational read service is not configured.',
        );
      }

      switch (intent) {
        case CustomerBalanceReadIntent():
          final result = await queries.customerBalance(intent.customerQuery);
          if (result.balances.isEmpty) {
            _runtimeMessages.add(
              SaleChatMessage(
                role: 'assistant',
                text: 'رصيد ${result.customerName}: 0. لا توجد حركة مدينة أو دائنة مسجلة في دفتر العميل المحلي.',
              ),
            );
            return;
          }
          final balances = result.balances
              .map((balance) =>
                  '${_formatMoneyScaled(balance.balanceScaled)} ${balance.currencyCode}')
              .join('، ');
          _runtimeMessages.add(
            SaleChatMessage(
              role: 'assistant',
              text: 'الرصيد الحالي للعميل ${result.customerName}: $balances. هذه قراءة مباشرة من دفتر العميل المحلي ولم تُنشئ أي قيد أو حركة.',
            ),
          );
        case SupplierBalanceReadIntent():
          final result = await queries.supplierBalance(intent.supplierQuery);
          if (result.balances.isEmpty) {
            _runtimeMessages.add(
              SaleChatMessage(
                role: 'assistant',
                text: 'المستحق الحالي للمورد ${result.supplierName}: 0. لا توجد ذمة مستحقة مسجلة في دفتر المورد المحلي.',
              ),
            );
            return;
          }
          final balances = result.balances
              .map((balance) =>
                  '${_formatMoneyScaled(balance.balanceScaled)} ${balance.currencyCode}')
              .join('، ');
          _runtimeMessages.add(
            SaleChatMessage(
              role: 'assistant',
              text: 'المستحق الحالي للمورد ${result.supplierName}: $balances. هذه قراءة مباشرة من دفتر المورد المحلي ولم تُنشئ أي قيد أو دفعة.',
            ),
          );
        case InventoryBalanceReadIntent():
          final result = await queries.inventoryBalance(intent.productQuery);
          final balance = result.balance;
          if (balance == null) {
            _runtimeMessages.add(
              SaleChatMessage(
                role: 'assistant',
                text: 'لا يوجد رصيد مخزني مسجل للصنف ${result.productName} في المستودع المحدد.',
              ),
            );
            return;
          }
          _runtimeMessages.add(
            SaleChatMessage(
              role: 'assistant',
              text: 'مخزون ${result.productName}: ${_formatQuantityScaled(balance.quantityScaled)} وحدة أساسية. متوسط التكلفة الدفتري ${_formatMoneyScaled(balance.wacUnitCostScaled)} بعملة الأساس. هذه قراءة محلية فقط.',
            ),
          );
        case UnsupportedOperationalReadIntent():
          throw const DomainError(
            'READ_INTENT_UNSUPPORTED',
            'Unsupported operational read intent.',
          );
      }
    });
  }

  Future<void> _executeSaleIntent(String value) async {
    await _runOperation(() async {
      final intent = _interpreter.interpret(value);
      switch (intent) {
        case CreateSaleConversationIntent():
          final current = _runtimeDraft;
          if (current != null && !_terminal(current.state)) {
            throw const DomainError(
              'OPEN_DRAFT_EXISTS',
              'Finish or cancel the current draft before creating another.',
            );
          }
          final sale = intent.sale;
          _runtimeDraft = await workflow.create(
            CreateSaleDraftRequest(
              draftId: 'draft-sale-${DateTime.now().toUtc().microsecondsSinceEpoch}',
              customerQuery: sale.customerQuery,
              productQuery: sale.productQuery,
              unitQuery: sale.unitQuery,
              quantityText: sale.quantityText,
              unitPriceText: sale.unitPriceText,
              currencyCode: sale.currencyCode,
              warehouseId: defaultWarehouseId,
              createdAtUtc: DateTime.now().toUtc(),
              settlementMode: sale.settlementMode,
            ),
          );
          _runtimeMessages.add(
            SaleChatMessage(
              role: 'assistant',
              text: sale.settlementMode == 'credit'
                  ? 'جهزت مسودة بيع على الحساب من البيانات المحلية. راجع العميل والصنف والمبلغ ثم وافق عليها.'
                  : 'جهزت مسودة بيع نقدي من البيانات المحلية. راجعها قبل الموافقة.',
            ),
          );
        case ReviseSalePriceIntent():
          final current = _requireDraft();
          _runtimeDraft = await workflow.revisePrice(current.draftId, intent.priceText);
          _runtimeMessages.add(
            SaleChatMessage(
              role: 'assistant',
              text: 'عدّلت السعر إلى ${intent.priceText} ${viewData?.currencyCode ?? ''}. أصبحت المسودة إصدار ${_runtimeDraft!.version} وتحتاج موافقة جديدة.',
            ),
          );
        case ReviseSaleQuantityIntent():
          final current = _requireDraft();
          _runtimeDraft = await workflow.reviseQuantity(current.draftId, intent.quantityText);
          _runtimeMessages.add(
            SaleChatMessage(
              role: 'assistant',
              text: 'عدّلت الكمية إلى ${intent.quantityText}. أصبحت المسودة إصدار ${_runtimeDraft!.version} وتحتاج موافقة جديدة.',
            ),
          );
        case ApproveSaleDraftIntent():
          final current = _requireDraft();
          _runtimeDraft = await workflow.approve(current.draftId);
          _runtimeMessages.add(
            const SaleChatMessage(
              role: 'assistant',
              text: 'ثبتت الموافقة على هذه النسخة. لم يتم الترحيل بعد.',
            ),
          );
        case CancelSaleDraftIntent():
          final current = _requireDraft();
          _runtimeDraft = await workflow.cancel(current.draftId);
          _runtimeMessages.add(
            const SaleChatMessage(
              role: 'assistant',
              text: 'ألغيت المسودة دون أي أثر مالي أو مخزني.',
            ),
          );
        case PostSaleDraftIntent():
          final current = _requireDraft();
          final postingContext = await postingContextFactory(current);
          final result = await workflow.postApproved(
            draftId: current.draftId,
            context: postingContext,
          );
          _runtimeDraft = await workflow.loadRequired(current.draftId);
          final settlement = current.payload['settlement_mode'] == 'credit'
              ? 'وسُجل المبلغ على حساب العميل'
              : 'وسُجل التحصيل النقدي';
          _runtimeMessages.add(
            SaleChatMessage(
              role: 'assistant',
              text: 'تم ترحيل الفاتورة ${result.documentNo} بنجاح $settlement. القيد وحركة المخزون والتدقيق نُفذت ذريًا.',
            ),
          );
        case UnsupportedSaleIntent():
          _runtimeMessages.add(
            const SaleChatMessage(
              role: 'assistant',
              text: 'لم أتعرف على إجراء مسجل يمكن تنفيذه بأمان. حدّد الإجراء والعميل والصنف والكمية والوحدة والسعر والعملة وطريقة التسوية.',
            ),
          );
      }
    });
  }

  Future<void> _runOperation(Future<void> Function() action) async {
    if (_runtimeBusy) return;
    _runtimeBusy = true;
    _runtimeError = null;
    notifyListeners();
    try {
      await action();
    } on DomainError catch (error) {
      _runtimeError = error.code;
      _runtimeMessages.add(
        SaleChatMessage(
          role: 'assistant',
          text: 'لم أنفذ الطلب: ${error.code}. لم أعتبر العملية ناجحة.',
        ),
      );
    } catch (_) {
      _runtimeError = 'UNEXPECTED_OPERATION_FAILURE';
      _runtimeMessages.add(
        const SaleChatMessage(
          role: 'assistant',
          text: 'حدث خطأ غير متوقع. أوقفت الإجراء ولم أعتبره ناجحًا.',
        ),
      );
    } finally {
      _runtimeBusy = false;
      notifyListeners();
    }
  }

  String _formatMoneyScaled(int scaled) => _formatScaled(scaled, 10000, 4);

  String _formatQuantityScaled(int scaled) => _formatScaled(scaled, 1000000, 6);

  String _formatScaled(int scaled, int scale, int decimals) {
    final negative = scaled < 0;
    final absolute = scaled.abs();
    final whole = absolute ~/ scale;
    final remainder = absolute % scale;
    if (remainder == 0) return '${negative ? '-' : ''}$whole';
    final fraction = remainder
        .toString()
        .padLeft(decimals, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '${negative ? '-' : ''}$whole.$fraction';
  }

  OperationalDraft _requireDraft() {
    final current = _runtimeDraft;
    if (current == null) {
      throw const DomainError('DRAFT_NOT_FOUND', 'No active sale draft exists.');
    }
    return current;
  }

  bool _terminal(OperationalDraftState state) =>
      state == OperationalDraftState.cancelled ||
      state == OperationalDraftState.expired ||
      state == OperationalDraftState.posted;

  @override
  SaleDraftViewData? get viewData {
    final current = _runtimeDraft;
    if (current == null) return null;
    final lines = current.payload['lines'];
    if (lines is! List || lines.length != 1 || lines.single is! Map) return null;
    final line = lines.single as Map;
    final customerName = current.payload['customer_name'];
    final currencyCode = current.payload['currency_code'];
    final productName = line['product_name'];
    final unitName = line['unit_name'];
    final quantityScaled = line['quantity_scaled'];
    final quantityPrecision = line['quantity_precision'];
    final unitPriceScaled = line['unit_price_scaled'];
    if (customerName is! String ||
        currencyCode is! String ||
        productName is! String ||
        unitName is! String ||
        quantityScaled is! int ||
        quantityPrecision is! int ||
        unitPriceScaled is! int) {
      return null;
    }
    return SaleDraftViewData(
      customerName: customerName,
      warehouseName: defaultWarehouseId == 'WH-MAIN' || defaultWarehouseId == 'WH-1'
          ? 'المستودع الرئيسي'
          : defaultWarehouseId,
      productName: productName,
      unitName: unitName,
      quantityScaled: quantityScaled,
      quantityPrecision: quantityPrecision,
      unitPriceScaled: unitPriceScaled,
      currencyCode: currencyCode,
      version: current.version,
      state: current.state,
    );
  }
}
