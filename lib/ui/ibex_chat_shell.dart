import 'package:flutter/material.dart';

import '../agent/operational_draft.dart';
import '../presentation/sale_chat_controller.dart';

class IbexVisualApp extends StatelessWidget {
  const IbexVisualApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0D6B57);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      title: 'IBEX 2.0',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          surface: const Color(0xFFF7F8F6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8F6),
        fontFamilyFallback: const ['Noto Sans Arabic', 'Noto Sans'],
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: IbexChatShell(),
      ),
    );
  }
}

class IbexChatShell extends StatefulWidget {
  const IbexChatShell({super.key, this.controller});

  final SaleChatController? controller;

  @override
  State<IbexChatShell> createState() => _IbexChatShellState();
}

class _IbexChatShellState extends State<IbexChatShell> {
  final composer = TextEditingController();
  late final SaleChatController controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    controller = widget.controller ?? SaleChatController.demo();
    controller.addListener(_refresh);
    controller.initializeDemoDraft();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    if (ownsController) controller.dispose();
    composer.dispose();
    super.dispose();
  }

  void submit() {
    final value = composer.text.trim();
    if (value.isEmpty) return;
    controller.submitNaturalLanguage(value);
    composer.clear();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        return Scaffold(
          drawer: wide ? null : const Drawer(child: _Sidebar()),
          body: SafeArea(
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                if (wide) const SizedBox(width: 260, child: _Sidebar()),
                Expanded(
                  child: Column(
                    children: [
                      _Header(showMenu: !wide),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: ListView(
                              key: const ValueKey('ibex-conversation-scroll'),
                              padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                              children: [
                                const _Welcome(),
                                const SizedBox(height: 22),
                                const _UserBubble(
                                  text:
                                      'أنشئ فاتورة مبيعات لصنف السدر عبوة كيلو، الكمية 1، السعر 500 ريال سعودي، على حساب محمد عبدالله باحكم.',
                                ),
                                const SizedBox(height: 14),
                                if (controller.busy)
                                  const _AgentLine(text: 'أجهز المسودة وأتحقق من البيانات…')
                                else if (controller.lastError != null)
                                  _AgentLine(text: 'تعذر تجهيز المسودة: ${controller.lastError}')
                                else if (controller.viewData != null)
                                  _AgentDraft(
                                    data: controller.viewData!,
                                    onApprove: controller.approve,
                                    onEdit: controller.requestEditTo400,
                                    onCancel: controller.cancel,
                                  ),
                                for (final message in controller.messages) ...[
                                  const SizedBox(height: 16),
                                  if (message.role == 'user')
                                    _UserBubble(text: message.text)
                                  else
                                    _AgentLine(text: message.text),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      _Composer(controller: composer, onSubmit: submit),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.showMenu});
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E9E6))),
      ),
      child: Row(
        children: [
          if (showMenu)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'القائمة',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('IBEX', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('المساعد التشغيلي', style: TextStyle(fontSize: 12, color: Color(0xFF68736D))),
              ],
            ),
          ),
          const _SafePill(),
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz_rounded)),
        ],
      ),
    );
  }
}

class _SafePill extends StatelessWidget {
  const _SafePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 15, color: Color(0xFF0D6B57)),
          SizedBox(width: 5),
          Text('محلي وآمن', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0D6B57))),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.receipt_long_outlined, 'المبيعات'),
      (Icons.shopping_bag_outlined, 'المشتريات'),
      (Icons.people_alt_outlined, 'العملاء'),
      (Icons.inventory_2_outlined, 'المخزون'),
      (Icons.account_balance_wallet_outlined, 'النقدية'),
      (Icons.bar_chart_rounded, 'التقارير'),
    ];
    return Container(
      color: const Color(0xFFF0F3F0),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(5, 6, 5, 18),
            child: Row(
              children: [
                _BrandMark(),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IBEX 2.0', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text('تشغيل ذكي', style: TextStyle(fontSize: 12, color: Color(0xFF68736D))),
                  ],
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded),
            label: const Text('محادثة جديدة'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              alignment: Alignment.centerRight,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),
          for (final item in items)
            TextButton.icon(
              onPressed: () {},
              icon: Icon(item.$1, size: 20),
              label: Text(item.$2),
              style: TextButton.styleFrom(
                alignment: Alignment.centerRight,
                minimumSize: const Size.fromHeight(44),
                foregroundColor: const Color(0xFF26322C),
              ),
            ),
          const Spacer(),
          const Divider(),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
            label: const Text('الإعدادات'),
            style: TextButton.styleFrom(alignment: Alignment.centerRight, foregroundColor: const Color(0xFF26322C)),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFF0D6B57), borderRadius: BorderRadius.circular(12)),
      child: const Text('I', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BrandMark(),
        const SizedBox(height: 14),
        const Text('ماذا تريد أن تنجز اليوم؟', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
        const SizedBox(height: 6),
        const Text(
          'اطلب إجراءً تشغيليًا بلغة طبيعية. سأجهز المسودة وأعرضها عليك قبل أي اعتماد.',
          style: TextStyle(color: Color(0xFF66716B), height: 1.5),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _PromptChip('أنشئ فاتورة بيع'),
            _PromptChip('كم رصيد محمد؟'),
            _PromptChip('اعرض مخزون السدر'),
          ],
        ),
      ],
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE1E5E2)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFE9EEEB), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(fontSize: 15, height: 1.5)),
      ),
    );
  }
}

class _AgentLine extends StatelessWidget {
  const _AgentLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AgentMark(),
        const SizedBox(width: 10),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: const TextStyle(height: 1.5)))),
      ],
    );
  }
}

class _AgentMark extends StatelessWidget {
  const _AgentMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFF0D6B57), borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 17),
    );
  }
}

class _AgentDraft extends StatelessWidget {
  const _AgentDraft({
    required this.data,
    required this.onApprove,
    required this.onEdit,
    required this.onCancel,
  });

  final SaleDraftViewData data;
  final VoidCallback onApprove;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AgentMark(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.version == 1
                    ? 'جهزت مسودة الفاتورة من عقد CreateSaleDraft. راجعها قبل الاعتماد.'
                    : 'تم تحديث المسودة إلى الإصدار ${data.version}. تحتاج مراجعة وموافقة جديدة.',
              ),
              const SizedBox(height: 10),
              _SaleDraftCard(data: data, onApprove: onApprove, onEdit: onEdit, onCancel: onCancel),
            ],
          ),
        ),
      ],
    );
  }
}

class _SaleDraftCard extends StatelessWidget {
  const _SaleDraftCard({required this.data, required this.onApprove, required this.onEdit, required this.onCancel});

  final SaleDraftViewData data;
  final VoidCallback onApprove;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  String get statusText => switch (data.state) {
        OperationalDraftState.awaitingApproval => 'بانتظار الموافقة',
        OperationalDraftState.approved => 'تمت الموافقة',
        OperationalDraftState.cancelled => 'ملغاة',
        OperationalDraftState.expired => 'منتهية',
        OperationalDraftState.posted => 'تم الترحيل',
        OperationalDraftState.draftReady => 'مسودة',
      };

  @override
  Widget build(BuildContext context) {
    final terminal = data.state == OperationalDraftState.cancelled ||
        data.state == OperationalDraftState.expired ||
        data.state == OperationalDraftState.posted;
    return Container(
      key: const ValueKey('sale-draft-card'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE3DF)),
        boxShadow: const [BoxShadow(blurRadius: 24, offset: Offset(0, 8), color: Color(0x0D1C2B24))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: const Color(0xFFEAF4F0), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.receipt_long_outlined, color: Color(0xFF0D6B57)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('مسودة فاتورة بيع', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text('الإصدار ${data.version} • لم تُرحّل محاسبيًا أو مخزنيًا', style: const TextStyle(fontSize: 11.5, color: Color(0xFF6A756F))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFEAF4F0), borderRadius: BorderRadius.circular(999)),
                      child: Text(statusText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _Info(label: 'العميل', value: data.customerName),
                _Info(label: 'المستودع', value: data.warehouseName),
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: const Color(0xFFF7F8F6), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data.productName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('الوحدة: ${data.unitName}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF6A756F))),
                          ],
                        ),
                      ),
                      Text('${data.quantityText} × ${data.unitPriceText} ${data.currencyCode}', textDirection: TextDirection.ltr),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w700))),
                    Text(
                      '${data.totalText} ${data.currencyCode}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFBF9),
              border: Border(top: BorderSide(color: Color(0xFFE6EAE7))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('approve-draft'),
                    onPressed: terminal || data.state == OperationalDraftState.approved ? null : onApprove,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(data.state == OperationalDraftState.approved ? 'موافق عليها' : 'اعتماد'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const ValueKey('edit-draft'),
                  onPressed: terminal ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('تعديل'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(96, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  key: const ValueKey('cancel-draft'),
                  tooltip: 'إلغاء المسودة',
                  onPressed: terminal ? null : onCancel,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF748078)))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 13),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE5E9E6)))),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('ibex-composer'),
                controller: controller,
                minLines: 1,
                maxLines: 5,
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: 'اطلب من IBEX تنفيذ إجراء…',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFFE1E5E2))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFFE1E5E2))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFF0D6B57), width: 1.5)),
                  prefixIcon: IconButton(onPressed: () {}, icon: const Icon(Icons.add_circle_outline_rounded)),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(5),
                    child: IconButton.filled(
                      key: const ValueKey('ibex-send'),
                      onPressed: onSubmit,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'المعاينة لا تُنشئ قيودًا أو حركات مخزون حتى يتم الاعتماد والترحيل عبر المحرك التشغيلي.',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF7A847F)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
