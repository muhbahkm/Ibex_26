import 'package:flutter/material.dart';

import '../agent/operational_draft.dart';
import '../presentation/sale_chat_controller.dart';

class IbexOperationalShell extends StatefulWidget {
  const IbexOperationalShell({super.key, required this.controller});

  final SaleChatController controller;

  @override
  State<IbexOperationalShell> createState() => _IbexOperationalShellState();
}

class _IbexOperationalShellState extends State<IbexOperationalShell> {
  final _composer = TextEditingController();
  String _section = 'assistant';

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

  void _select(String section) {
    setState(() => _section = section);
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) Navigator.of(context).pop();
  }

  void _submit([String? text]) {
    final value = (text ?? _composer.text).trim();
    if (value.isEmpty) return;
    setState(() => _section = 'assistant');
    controller.submitNaturalLanguage(value);
    _composer.clear();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final sidebar = _Sidebar(selected: _section, onSelect: _select);
        return Scaffold(
          drawer: wide ? null : Drawer(child: sidebar),
          body: SafeArea(
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                if (wide) SizedBox(width: 260, child: sidebar),
                Expanded(
                  child: Column(
                    children: [
                      _Header(showMenu: !wide, title: _titleFor(_section)),
                      Expanded(child: _body()),
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

  String _titleFor(String section) => switch (section) {
        'sales' => 'المبيعات',
        'purchases' => 'المشتريات',
        'customers' => 'العملاء',
        'inventory' => 'المخزون',
        'cash' => 'النقدية',
        'reports' => 'التقارير',
        'settings' => 'الإعدادات',
        _ => 'المساعد التشغيلي',
      };

  Widget _body() {
    if (_section == 'assistant') return _assistant();
    final spec = _moduleSpec(_section);
    return _ModulePage(
      title: spec.title,
      subtitle: spec.subtitle,
      icon: spec.icon,
      capabilities: spec.capabilities,
      onAskAssistant: () {
        _composer.text = spec.suggestedPrompt;
        setState(() => _section = 'assistant');
      },
    );
  }

  Widget _assistant() {
    final data = controller.viewData;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
            children: [
              const _WelcomeTitle(),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionChip(
                    label: 'أنشئ فاتورة بيع',
                    onTap: () => _submit(
                      'أنشئ فاتورة مبيعات لصنف السدر عبوة كيلو، الكمية 1، السعر 500 ريال سعودي، على حساب محمد عبدالله باحكم.',
                    ),
                  ),
                  _ActionChip(
                    label: 'افتح المبيعات',
                    onTap: () => _select('sales'),
                  ),
                  _ActionChip(
                    label: 'افتح المخزون',
                    onTap: () => _select('inventory'),
                  ),
                ],
              ),
              if (controller.busy) ...[
                const SizedBox(height: 20),
                const LinearProgressIndicator(),
              ],
              if (controller.lastError != null) ...[
                const SizedBox(height: 20),
                _Notice('تعذر تنفيذ الطلب: ${controller.lastError}'),
              ],
              if (data != null) ...[
                const SizedBox(height: 20),
                _DraftCard(
                  data: data,
                  onApprove: controller.approve,
                  onCancel: controller.cancel,
                ),
              ],
              for (final message in controller.messages) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: message.role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 620),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: message.role == 'user' ? const Color(0xFFE8EEEA) : Colors.white,
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
            color: Color(0xFFF7F8F6),
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
              prefixIcon: const Icon(Icons.add_circle_outline_rounded),
              suffixIcon: IconButton(
                onPressed: _submit,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: Color(0xFF0D6B57)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.showMenu, required this.title});
  final bool showMenu;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE5E9E6)))),
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
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('IBEX', style: TextStyle(fontWeight: FontWeight.w900)),
                Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF68736D))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFEAF4F0), borderRadius: BorderRadius.circular(99)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 15, color: Color(0xFF0D6B57)),
                SizedBox(width: 5),
                Text('محلي وآمن', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0D6B57))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

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
    ];
    return Container(
      color: const Color(0xFFF0F3F0),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 4),
            leading: CircleAvatar(
              backgroundColor: Color(0xFF0D6B57),
              child: Text('I', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            title: Text('IBEX 2.0', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('المالك المحلي'),
          ),
          const SizedBox(height: 10),
          for (final item in items)
            ListTile(
              selected: selected == item.$1,
              selectedTileColor: const Color(0xFFE3EEE9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: Icon(item.$2),
              title: Text(item.$3),
              onTap: () => onSelect(item.$1),
            ),
          const Spacer(),
          const Divider(),
          ListTile(
            selected: selected == 'settings',
            selectedTileColor: const Color(0xFFE3EEE9),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.settings_outlined),
            title: const Text('الإعدادات'),
            onTap: () => onSelect('settings'),
          ),
        ],
      ),
    );
  }
}

class _WelcomeTitle extends StatelessWidget {
  const _WelcomeTitle();
  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ماذا تريد أن تنجز اليوم؟', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          SizedBox(height: 6),
          Text('لا يلزم تسجيل دخول. يعمل IBEX محليًا على هذا الجهاز، ويطلب اعتمادك قبل الترحيل.', style: TextStyle(color: Color(0xFF68736D), height: 1.5)),
        ],
      );
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ActionChip(label: Text(label), onPressed: onTap);
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFDCE3DE)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مسودة فاتورة بيع', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text('العميل: ${data.customerName}'),
            Text('الصنف: ${data.productName}'),
            Text('الكمية: ${data.quantityText}'),
            Text('الإجمالي: ${data.totalText} ${data.currencyCode}', textDirection: TextDirection.rtl),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: terminal || data.state == OperationalDraftState.approved ? null : onApprove,
                    child: Text(data.state == OperationalDraftState.approved ? 'تم الاعتماد' : 'اعتماد'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: terminal ? null : onCancel, child: const Text('إلغاء')),
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
        decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(14)),
        child: Text(text),
      );
}

class _ModulePage extends StatelessWidget {
  const _ModulePage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.capabilities,
    required this.onAskAssistant,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> capabilities;
  final VoidCallback onAskAssistant;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              CircleAvatar(radius: 24, backgroundColor: const Color(0xFFEAF4F0), child: Icon(icon, color: const Color(0xFF0D6B57))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    Text(subtitle, style: const TextStyle(color: Color(0xFF68736D))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          for (final capability in capabilities)
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF0D6B57)),
                title: Text(capability),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAskAssistant,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('اطلب إجراءً من المساعد'),
          ),
        ],
      );
}

({String title, String subtitle, IconData icon, List<String> capabilities, String suggestedPrompt}) _moduleSpec(String section) {
  return switch (section) {
    'sales' => (
        title: 'المبيعات',
        subtitle: 'الفواتير، المرتجعات والتحصيل',
        icon: Icons.receipt_long_outlined,
        capabilities: ['إنشاء مسودة بيع', 'اعتماد قبل الترحيل', 'حماية المخزون والقيد المحاسبي'],
        suggestedPrompt: 'أنشئ فاتورة بيع جديدة',
      ),
    'purchases' => (
        title: 'المشتريات',
        subtitle: 'الموردون والمشتريات والمرتجعات',
        icon: Icons.shopping_bag_outlined,
        capabilities: ['محرك شراء ذري', 'شراء نقدي أو آجل', 'مرتجع شراء مضبوط بالمصدر'],
        suggestedPrompt: 'أريد تسجيل فاتورة شراء',
      ),
    'customers' => (
        title: 'العملاء',
        subtitle: 'الأرصدة والحركات والتحصيل',
        icon: Icons.people_alt_outlined,
        capabilities: ['رصيد العميل من دفتر الأستاذ', 'تحصيل دفعة عميل', 'سجل حركات قابل للتدقيق'],
        suggestedPrompt: 'اعرض رصيد العميل محمد عبدالله باحكم',
      ),
    'inventory' => (
        title: 'المخزون',
        subtitle: 'الأرصدة والتحويلات والحركة',
        icon: Icons.inventory_2_outlined,
        capabilities: ['رصيد مخزون محلي', 'تحويل بين المستودعات', 'منع السالب قبل الترحيل'],
        suggestedPrompt: 'اعرض مخزون السدر',
      ),
    'cash' => (
        title: 'النقدية',
        subtitle: 'الصندوق والمصروفات والمدفوعات',
        icon: Icons.account_balance_wallet_outlined,
        capabilities: ['مصروف نقدي', 'دفع مورد', 'عكس مصروف بمستند تعويضي'],
        suggestedPrompt: 'سجل مصروفًا نقديًا',
      ),
    'reports' => (
        title: 'التقارير',
        subtitle: 'قراءة الحقيقة التشغيلية والمحاسبية',
        icon: Icons.bar_chart_rounded,
        capabilities: ['ميزان مراجعة', 'قراءات بدون أي كتابة', 'تسويات مبنية على القيود الفعلية'],
        suggestedPrompt: 'اعرض تقريرًا تشغيليًا',
      ),
    _ => (
        title: 'الإعدادات',
        subtitle: 'التشغيل المحلي والأمان',
        icon: Icons.settings_outlined,
        capabilities: ['المالك المحلي يعمل بلا تسجيل دخول', 'قاعدة بيانات محلية مشفرة', 'الصلاحيات تبقى داخلية لأغراض الحماية والتدقيق'],
        suggestedPrompt: 'افتح إعدادات IBEX',
      ),
  };
}
