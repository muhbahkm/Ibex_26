import 'package:flutter/material.dart';

import '../agent/operational_draft.dart';
import '../presentation/sale_chat_controller.dart';
import 'gemini_settings_page.dart';

class IbexOperationalShellV2 extends StatefulWidget {
  const IbexOperationalShellV2({super.key, required this.controller});

  final SaleChatController controller;

  @override
  State<IbexOperationalShellV2> createState() => _IbexOperationalShellV2State();
}

class _IbexOperationalShellV2State extends State<IbexOperationalShellV2> {
  final _composer = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<String> _history = <String>['assistant'];

  String get _section => _history.last;
  bool get _canGoBack => _history.length > 1;
  SaleChatController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    controller.initialize();
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    _composer.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _navigateTo(String value, {bool replace = false}) {
    if (value == _section) return;
    setState(() {
      if (replace && _history.isNotEmpty) {
        _history[_history.length - 1] = value;
      } else {
        _history.add(value);
      }
    });
  }

  void _goBack() {
    if (!_canGoBack) return;
    setState(() => _history.removeLast());
  }

  void _submit([String? text]) {
    final value = (text ?? _composer.text).trim();
    if (value.isEmpty) return;
    _navigateTo('assistant');
    controller.submitNaturalLanguage(value);
    _composer.clear();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final side = _Sidebar(
          selected: _section,
          onSelect: _navigateTo,
          dismissOnSelect: !wide,
        );

        return PopScope(
          canPop: !_canGoBack,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _goBack();
          },
          child: Scaffold(
            key: _scaffoldKey,
            drawerEnableOpenDragGesture: !wide,
            drawerScrimColor: Colors.black.withValues(alpha: 0.28),
            drawer: wide
                ? null
                : Drawer(
                    width: MediaQuery.sizeOf(context).width * 0.82,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.horizontal(left: Radius.circular(22)),
                    ),
                    child: SafeArea(child: side),
                  ),
            body: SafeArea(
              child: Row(
                textDirection: TextDirection.ltr,
                children: [
                  if (wide) SizedBox(width: 260, child: side),
                  Expanded(
                    child: Column(
                      children: [
                        _Header(
                          showMenu: !wide,
                          showBack: _canGoBack,
                          title: _title(_section),
                          onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                          onBack: _goBack,
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            reverseDuration: const Duration(milliseconds: 170),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0.035, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(position: slide, child: child),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey<String>(_section),
                              child: _body(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _title(String section) => switch (section) {
        'sales' => 'المبيعات',
        'purchases' => 'المشتريات',
        'customers' => 'العملاء',
        'inventory' => 'المخزون',
        'cash' => 'النقدية',
        'reports' => 'التقارير',
        'settings' => 'الإعدادات والذكاء الاصطناعي',
        _ => 'المساعد التشغيلي',
      };

  Widget _body() {
    if (_section == 'assistant') return _assistant();
    if (_section == 'settings') return const GeminiSettingsPage();
    final spec = _spec(_section);
    return _ModulePage(
      title: spec.title,
      subtitle: spec.subtitle,
      icon: spec.icon,
      actions: spec.actions,
      onAsk: () {
        _composer.text = spec.prompt;
        _navigateTo('assistant');
      },
    );
  }

  Widget _assistant() {
    final draft = controller.viewData;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const Text(
                'ماذا تريد أن تنجز اليوم؟',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'IBEX يعمل محليًا دون تسجيل دخول. Gemini يساعد في فهم الطلب فقط، والتنفيذ يبقى داخل المحرك المحلي بعد التحقق والموافقة.',
                style: TextStyle(color: Color(0xFF68736D), height: 1.5),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('أنشئ فاتورة بيع'),
                    onPressed: () => _submit(
                      'أنشئ فاتورة بيع لصنف سدر عبوة كيلو بكمية 1 الوحدة جالون بسعر 500 SAR على حساب محمد عبدالله باحكم',
                    ),
                  ),
                  ActionChip(
                    label: const Text('اعرض المخزون'),
                    onPressed: () => _submit('اعرض مخزون سدر عبوة كيلو'),
                  ),
                  ActionChip(
                    label: const Text('إعداد Gemini'),
                    onPressed: () => _navigateTo('settings'),
                  ),
                ],
              ),
              if (controller.busy) ...[
                const SizedBox(height: 18),
                const LinearProgressIndicator(),
              ],
              if (controller.lastError != null) ...[
                const SizedBox(height: 16),
                _Notice('تعذر تنفيذ الطلب: ${controller.lastError}'),
              ],
              if (draft != null) ...[
                const SizedBox(height: 18),
                _DraftCard(
                  data: draft,
                  onApprove: controller.approve,
                  onCancel: controller.cancel,
                ),
              ],
              for (final message in controller.messages) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: message.role == 'user'
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 620),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: message.role == 'user'
                          ? const Color(0xFFE8EEEA)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E7E3)),
                    ),
                    child: Text(message.text, style: const TextStyle(height: 1.5)),
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE4E8E5))),
          ),
          child: TextField(
            controller: _composer,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'اطلب من IBEX تنفيذ إجراء…',
              filled: true,
              fillColor: Colors.white,
              suffixIcon: IconButton(
                onPressed: _submit,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.showMenu,
    required this.showBack,
    required this.title,
    required this.onMenu,
    required this.onBack,
  });

  final bool showMenu;
  final bool showBack;
  final String title;
  final VoidCallback onMenu;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE5E9E6))),
        ),
        child: Row(
          children: [
            if (showMenu)
              IconButton(
                tooltip: 'القائمة',
                onPressed: onMenu,
                icon: const Icon(Icons.menu_rounded),
              ),
            if (showBack)
              IconButton(
                tooltip: 'رجوع',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('IBEX', style: TextStyle(fontWeight: FontWeight.w900)),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF68736D)),
                  ),
                ],
              ),
            ),
            const Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(Icons.shield_outlined, size: 16),
              label: Text('محلي وآمن'),
            ),
          ],
        ),
      );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.onSelect,
    required this.dismissOnSelect,
  });

  final String selected;
  final ValueChanged<String> onSelect;
  final bool dismissOnSelect;

  void _select(BuildContext context, String section) {
    if (dismissOnSelect) {
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) => onSelect(section));
      return;
    }
    onSelect(section);
  }

  @override
  Widget build(BuildContext context) {
    const items = [
      ('assistant', Icons.auto_awesome_outlined, 'المساعد'),
      ('sales', Icons.receipt_long_outlined, 'المبيعات'),
      ('purchases', Icons.shopping_bag_outlined, 'المشتريات'),
      ('customers', Icons.people_alt_outlined, 'العملاء'),
      ('inventory', Icons.inventory_2_outlined, 'المخزون'),
      ('cash', Icons.account_balance_wallet_outlined, 'النقدية'),
      ('reports', Icons.bar_chart_rounded, 'التقارير'),
      ('settings', Icons.settings_outlined, 'الإعدادات'),
    ];
    return Material(
      color: const Color(0xFFF0F3F0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(0xFF0D6B57),
                child: Text('I', style: TextStyle(color: Colors.white)),
              ),
              title: Text('IBEX 2.0', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('المالك المحلي'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        selected: selected == item.$1,
                        selectedTileColor: const Color(0xFFE3EEE9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Icon(item.$2),
                        title: Text(item.$3),
                        trailing: selected == item.$1
                            ? const Icon(Icons.check_rounded, size: 18)
                            : null,
                        onTap: () => _select(context, item.$1),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.data, required this.onApprove, required this.onCancel});
  final SaleDraftViewData data;
  final VoidCallback onApprove;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final terminal = data.state == OperationalDraftState.cancelled ||
        data.state == OperationalDraftState.expired ||
        data.state == OperationalDraftState.posted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مسودة فاتورة بيع', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('العميل: ${data.customerName}'),
            Text('الصنف: ${data.productName}'),
            Text('الكمية: ${data.quantityText}'),
            Text('الإجمالي: ${data.totalText} ${data.currencyCode}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: terminal || data.state == OperationalDraftState.approved
                        ? null
                        : onApprove,
                    child: Text(data.state == OperationalDraftState.approved ? 'تم الاعتماد' : 'اعتماد'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: terminal ? null : onCancel,
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text),
      );
}

class _ModulePage extends StatelessWidget {
  const _ModulePage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    required this.onAsk,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> actions;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Icon(icon)),
            title: Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            subtitle: Text(subtitle),
          ),
          const SizedBox(height: 16),
          for (final action in actions)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: Text(action),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAsk,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('اطلب إجراءً من المساعد'),
          ),
        ],
      );
}

({String title, String subtitle, IconData icon, List<String> actions, String prompt})
    _spec(String section) => switch (section) {
          'sales' => (
              title: 'المبيعات',
              subtitle: 'الفواتير والمرتجعات والتحصيل',
              icon: Icons.receipt_long_outlined,
              actions: ['إنشاء مسودة بيع', 'الموافقة قبل الترحيل', 'حماية المخزون والقيد'],
              prompt: 'أنشئ فاتورة بيع جديدة',
            ),
          'purchases' => (
              title: 'المشتريات',
              subtitle: 'الموردون والمشتريات والمرتجعات',
              icon: Icons.shopping_bag_outlined,
              actions: ['شراء نقدي أو آجل', 'دفع المورد', 'مرتجع مرتبط بالمصدر'],
              prompt: 'أريد تسجيل فاتورة شراء',
            ),
          'customers' => (
              title: 'العملاء',
              subtitle: 'الأرصدة والحركات والتحصيل',
              icon: Icons.people_alt_outlined,
              actions: ['رصيد العميل', 'تحصيل دفعة', 'سجل حركات قابل للتدقيق'],
              prompt: 'اعرض رصيد العميل محمد عبدالله باحكم',
            ),
          'inventory' => (
              title: 'المخزون',
              subtitle: 'الأرصدة والتحويلات والحركة',
              icon: Icons.inventory_2_outlined,
              actions: ['رصيد الصنف', 'تحويل مستودعات', 'منع المخزون السالب'],
              prompt: 'اعرض مخزون السدر',
            ),
          'cash' => (
              title: 'النقدية',
              subtitle: 'الصندوق والمصروفات والمدفوعات',
              icon: Icons.account_balance_wallet_outlined,
              actions: ['مصروف نقدي', 'دفع مورد', 'عكس مصروف بمستند تعويضي'],
              prompt: 'سجل مصروفًا نقديًا',
            ),
          _ => (
              title: 'التقارير',
              subtitle: 'قراءة الحقيقة التشغيلية والمحاسبية',
              icon: Icons.bar_chart_rounded,
              actions: ['ميزان مراجعة', 'قراءات بدون كتابة', 'تسويات مبنية على القيود'],
              prompt: 'اعرض تقريرًا تشغيليًا',
            ),
        };
