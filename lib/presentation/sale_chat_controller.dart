import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/approved_sale_draft_to_command.dart';
import '../agent/command_registry.dart';
import '../agent/create_sale_draft_service.dart';
import '../agent/operational_draft.dart';
import '../agent/revise_sale_draft_service.dart';
import '../agent/sale_intent_interpreter.dart';
import '../agent/sale_operational_workflow.dart';
import '../core/errors/domain_error.dart';

class SaleChatMessage {
  const SaleChatMessage({required this.role, required this.text});
  final String role;
  final String text;
}

class SaleDraftViewData {
  const SaleDraftViewData({
    required this.customerName,
    required this.warehouseName,
    required this.productName,
    required this.unitName,
    required this.quantityScaled,
    required this.quantityPrecision,
    required this.unitPriceScaled,
    required this.currencyCode,
    required this.version,
    required this.state,
  });

  final String customerName;
  final String warehouseName;
  final String productName;
  final String unitName;
  final int quantityScaled;
  final int quantityPrecision;
  final int unitPriceScaled;
  final String currencyCode;
  final int version;
  final OperationalDraftState state;

  String get quantityText {
    const scale = 1000000;
    final whole = quantityScaled ~/ scale;
    final fraction = (quantityScaled % scale).abs().toString().padLeft(6, '0');
    if (quantityPrecision == 0) return '$whole';
    return '$whole.${fraction.substring(0, quantityPrecision)}';
  }

  String get unitPriceText {
    const scale = 10000;
    final whole = unitPriceScaled ~/ scale;
    final remainder = (unitPriceScaled % scale).abs();
    if (remainder == 0) return '$whole';
    final fraction = remainder.toString().padLeft(4, '0').replaceFirst(RegExp(r'0+$'), '');
    return '$whole.$fraction';
  }

  String get totalText {
    final totalScaled = (unitPriceScaled * quantityScaled) ~/ 1000000;
    final whole = totalScaled ~/ 10000;
    final remainder = (totalScaled % 10000).abs();
    if (remainder == 0) return '$whole';
    final fraction = remainder.toString().padLeft(4, '0').replaceFirst(RegExp(r'0+$'), '');
    return '$whole.$fraction';
  }
}

typedef SalePostingContextFactory = FutureOr<SalePostingContext> Function(OperationalDraft draft);

class SaleChatController extends ChangeNotifier {
  SaleChatController({
    required CreateSaleDraftService createSaleDraft,
    ReviseSaleDraftService reviseSaleDraft = const ReviseSaleDraftService(),
    SaleOperationalWorkflow? workflow,
    SalePostingContextFactory? postingContextFactory,
    SaleIntentInterpreter interpreter = const SaleIntentInterpreter(),
    String defaultWarehouseId = 'WH-1',
  })  : _createSaleDraft = createSaleDraft,
        _reviseSaleDraft = reviseSaleDraft,
        _workflow = workflow,
        _postingContextFactory = postingContextFactory,
        _interpreter = interpreter,
        _defaultWarehouseId = defaultWarehouseId;

  factory SaleChatController.demo() {
    return SaleChatController(
      createSaleDraft: CreateSaleDraftService(
        catalog: const _DemoCatalog(),
        registry: const AgentCommandRegistry({CreateSaleDraftService.commandName}),
      ),
    );
  }

  factory SaleChatController.persistent({
    required SaleOperationalWorkflow workflow,
    required SalePostingContextFactory postingContextFactory,
    String defaultWarehouseId = 'WH-1',
  }) {
    return SaleChatController(
      createSaleDraft: workflow.createSaleDraft,
      workflow: workflow,
      postingContextFactory: postingContextFactory,
      defaultWarehouseId: defaultWarehouseId,
    );
  }

  final CreateSaleDraftService _createSaleDraft;
  final ReviseSaleDraftService _reviseSaleDraft;
  final SaleOperationalWorkflow? _workflow;
  final SalePostingContextFactory? _postingContextFactory;
  final SaleIntentInterpreter _interpreter;
  final String _defaultWarehouseId;

  OperationalDraft? _draft;
  bool _busy = false;
  String? _lastError;
  final List<SaleChatMessage> _messages = [];

  bool get busy => _busy;
  String? get lastError => _lastError;
  OperationalDraft? get draft => _draft;
  bool get persistent => _workflow != null;
  List<SaleChatMessage> get messages => List.unmodifiable(_messages);

  Future<void> initialize() async {
    final workflow = _workflow;
    if (workflow == null) {
      await initializeDemoDraft();
      return;
    }
    if (_busy) return;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      _draft = await workflow.loadLatestOpen();
      if (_draft != null) {
        _messages.add(
          SaleChatMessage(
            role: 'assistant',
            text: 'استعدت مسودة البيع المفتوحة رقم الإصدار ${_draft!.version}. راجعها قبل المتابعة.',
          ),
        );
      }
    } on DomainError catch (error) {
      _lastError = error.code;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> initializeDemoDraft() async {
    if (_draft != null || _busy) return;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      _draft = await _createSaleDraft.execute(
        CreateSaleDraftRequest(
          draftId: 'draft-sale-demo-1',
          customerQuery: 'محمد عبدالله باحكم',
          productQuery: 'سدر عبوة كيلو',
          unitQuery: 'جالون',
          quantityText: '1',
          unitPriceText: '500',
          currencyCode: 'SAR',
          warehouseId: 'warehouse-main',
          createdAtUtc: DateTime.now().toUtc(),
        ),
      );
    } on DomainError catch (error) {
      _lastError = error.code;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void approve() {
    final workflow = _workflow;
    if (workflow != null) {
      unawaited(_approvePersistent(workflow));
      return;
    }
    final current = _draft;
    if (current == null) return;
    try {
      _draft = current.approve();
      _lastError = null;
    } on DomainError catch (error) {
      _lastError = error.code;
    }
    notifyListeners();
  }

  void cancel() {
    final workflow = _workflow;
    if (workflow != null) {
      unawaited(_cancelPersistent(workflow));
      return;
    }
    final current = _draft;
    if (current == null) return;
    try {
      _draft = current.cancel();
      _lastError = null;
    } on DomainError catch (error) {
      _lastError = error.code;
    }
    notifyListeners();
  }

  void requestEditTo400() => revisePrice('400');

  void revisePrice(String priceText) {
    final workflow = _workflow;
    if (workflow != null) {
      unawaited(_revisePricePersistent(workflow, priceText));
      return;
    }
    final current = _draft;
    if (current == null) return;
    try {
      _draft = _reviseSaleDraft.execute(
        ReviseSaleDraftRequest(draft: current, unitPriceText: priceText),
      );
      _lastError = null;
    } on DomainError catch (error) {
      _lastError = error.code;
    }
    notifyListeners();
  }

  void submitNaturalLanguage(String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    _messages.add(SaleChatMessage(role: 'user', text: value));

    final workflow = _workflow;
    if (workflow != null) {
      notifyListeners();
      unawaited(_handlePersistentIntent(workflow, value));
      return;
    }

    final requestedPrice = _extractPriceRevision(value);
    if (requestedPrice != null && _draft != null) {
      revisePrice(requestedPrice);
      _messages.add(
        SaleChatMessage(
          role: 'assistant',
          text: 'عدّلت سعر المسودة إلى $requestedPrice ${viewData?.currencyCode ?? ''}. ألغيت الموافقة السابقة تلقائيًا، وتحتاج المسودة إلى مراجعة جديدة.',
        ),
      );
    } else {
      _messages.add(
        const SaleChatMessage(
          role: 'assistant',
          text: 'وصل الطلب. في هذه المرحلة التجريبية لا أنفذ إلا أوامر تعديل السعر المحددة؛ بقية النوايا ستُربط تباعًا بعقود تشغيلية آمنة.',
        ),
      );
    }
    notifyListeners();
  }

  Future<void> _handlePersistentIntent(SaleOperationalWorkflow workflow, String value) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final intent = _interpreter.interpret(value);
      switch (intent) {
        case CreateSaleConversationIntent():
          final current = _draft;
          if (current != null &&
              current.state != OperationalDraftState.cancelled &&
              current.state != OperationalDraftState.expired &&
              current.state != OperationalDraftState.posted) {
            throw const DomainError(
              'OPEN_DRAFT_EXISTS',
              'Finish or cancel the current draft before creating another sale draft.',
            );
          }
          final sale = intent.sale;
          final draftId = 'draft-sale-${DateTime.now().toUtc().microsecondsSinceEpoch}';
          _draft = await workflow.create(
            CreateSaleDraftRequest(
              draftId: draftId,
              customerQuery: sale.customerQuery,
              productQuery: sale.productQuery,
              unitQuery: sale.unitQuery,
              quantityText: sale.quantityText,
              unitPriceText: sale.unitPriceText,
              currencyCode: sale.currencyCode,
              warehouseId: _defaultWarehouseId,
              createdAtUtc: DateTime.now().toUtc(),
            ),
          );
          _messages.add(
            const SaleChatMessage(
              role: 'assistant',
              text: 'جهزت مسودة البيع من البيانات المحلية. لم أرحّل أي قيد أو حركة مخزون؛ راجع البطاقة ثم وافق عليها.',
            ),
          );
        case ReviseSalePriceIntent():
          final current = _requireDraft();
          _draft = await workflow.revisePrice(current.draftId, intent.priceText);
          _messages.add(
            SaleChatMessage(
              role: 'assistant',
              text: 'تم تعديل السعر إلى ${intent.priceText} ${viewData?.currencyCode ?? ''}. أصبحت المسودة إصدار ${_draft!.version} وتحتاج موافقة جديدة.',
            ),
          );
        case ReviseSaleQuantityIntent():
          final current = _requireDraft();
          _draft = await workflow.reviseQuantity(current.draftId, intent.quantityText);
          _messages.add(
            SaleChatMessage(
              role: 'assistant',
              text: 'تم تعديل الكمية إلى ${intent.quantityText}. أصبحت المسودة إصدار ${_draft!.version} وتحتاج موافقة جديدة.',
            ),
          );
        case ApproveSaleDraftIntent():
          final current = _requireDraft();
          _draft = await workflow.approve(current.draftId);
          _messages.add(
            const SaleChatMessage(
              role: 'assistant',
              text: 'تم تثبيت الموافقة على هذه النسخة من المسودة. لم يتم الترحيل بعد؛ اكتب «رحّل الفاتورة» للتنفيذ النهائي.',
            ),
          );
        case CancelSaleDraftIntent():
          final current = _requireDraft();
          _draft = await workflow.cancel(current.draftId);
          _messages.add(const SaleChatMessage(role: 'assistant', text: 'ألغيت المسودة دون إنشاء أي حقيقة محاسبية أو مخزنية.'));
        case PostSaleDraftIntent():
          final current = _requireDraft();
          final factory = _postingContextFactory;
          if (factory == null) {
            throw const DomainError('POSTING_CONTEXT_REQUIRED', 'Posting context is not configured.');
          }
          final result = await workflow.postApproved(
            draftId: current.draftId,
            context: await factory(current),
          );
          _draft = await workflow.loadRequired(current.draftId);
          _messages.add(
            SaleChatMessage(
              role: 'assistant',
              text: 'تم ترحيل فاتورة البيع بنجاح برقم ${result.documentNo}. أنشأ محرك IBEX القيد وحركة المخزون والدفع والتدقيق في معاملة واحدة.',
            ),
          );
        case UnsupportedSaleIntent():
          _messages.add(
            const SaleChatMessage(
              role: 'assistant',
              text: 'لم أتعرف على إجراء تشغيلي مسجل يمكن تنفيذه بأمان. أعد صياغة الطلب وحدد الصنف والكمية والوحدة والسعر والعملة والعميل.',
            ),
          );
      }
    } on DomainError catch (error) {
      _lastError = error.code;
      _messages.add(SaleChatMessage(role: 'assistant', text: 'لم أنفذ الطلب: ${error.code}. لم يتم تغيير الحقيقة التشغيلية.'));
    } catch (_) {
      _lastError = 'UNEXPECTED_OPERATION_FAILURE';
      _messages.add(
        const SaleChatMessage(
          role: 'assistant',
          text: 'حدث خطأ غير متوقع أثناء الإجراء. أوقفت التنفيذ ولم أعتبر العملية ناجحة.',
        ),
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _approvePersistent(SaleOperationalWorkflow workflow) async {
    final current = _draft;
    if (current == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      _draft = await workflow.approve(current.draftId);
      _lastError = null;
    } on DomainError catch (error) {
      _lastError = error.code;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _cancelPersistent(SaleOperationalWorkflow workflow) async {
    final current = _draft;
    if (current == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      _draft = await workflow.cancel(current.draftId);
      _lastError = null;
    } on DomainError catch (error) {
      _lastError = error.code;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _revisePricePersistent(SaleOperationalWorkflow workflow, String priceText) async {
    final current = _draft;
    if (current == null || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      _draft = await workflow.revisePrice(current.draftId, priceText);
      _lastError = null;
    } on DomainError catch (error) {
      _lastError = error.code;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  OperationalDraft _requireDraft() {
    final current = _draft;
    if (current == null) {
      throw const DomainError('DRAFT_NOT_FOUND', 'No active sale draft exists.');
    }
    return current;
  }

  SaleDraftViewData? get viewData {
    final current = _draft;
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
      warehouseName: _defaultWarehouseId == 'WH-1' || _defaultWarehouseId == 'warehouse-main'
          ? 'المستودع الرئيسي'
          : _defaultWarehouseId,
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

  String? _extractPriceRevision(String value) {
    final normalized = value.replaceAll('،', ' ').replaceAll(',', ' ');
    final mentionsPrice = normalized.contains('السعر') ||
        normalized.contains('المبلغ') ||
        normalized.contains('اجعل') ||
        normalized.contains('عدّل') ||
        normalized.contains('عدل');
    if (!mentionsPrice) return null;
    final matches = RegExp(r'(?<![\d.])(\d+(?:\.\d{1,4})?)(?![\d.])').allMatches(normalized).toList();
    if (matches.length != 1) return null;
    return matches.single.group(1);
  }
}

class _DemoCatalog implements SaleDraftCatalog {
  const _DemoCatalog();

  @override
  Future<List<SaleDraftCustomer>> findCustomers(String query) async => const [
        SaleDraftCustomer(id: 'customer-1', name: 'محمد عبدالله باحكم'),
      ];

  @override
  Future<List<SaleDraftProduct>> findProducts(String query) async => const [
        SaleDraftProduct(id: 'product-1', name: 'سدر — عبوة كيلو'),
      ];

  @override
  Future<List<SaleDraftUnit>> findUnitsForProduct(String productId, String query) async => const [
        SaleDraftUnit(id: 'unit-1', name: 'جالون', quantityPrecision: 0),
      ];
}
