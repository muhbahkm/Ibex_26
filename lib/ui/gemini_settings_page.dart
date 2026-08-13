import 'package:flutter/material.dart';

import '../ai/gemini_api_key_store.dart';
import '../ai/gemini_provider.dart';
import '../ai/gemini_settings_controller.dart';

class GeminiSettingsPage extends StatefulWidget {
  const GeminiSettingsPage({super.key, this.controller});

  final GeminiSettingsController? controller;

  @override
  State<GeminiSettingsPage> createState() => _GeminiSettingsPageState();
}

class _GeminiSettingsPageState extends State<GeminiSettingsPage> {
  final _keyField = TextEditingController();
  late final GeminiSettingsController _controller;
  late final bool _ownsController;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    if (_ownsController) {
      final store = SecureGeminiApiKeyStore();
      _controller = GeminiSettingsController(
        keyStore: store,
        provider: GeminiProvider(keyStore: store),
      );
    } else {
      _controller = widget.controller!;
    }
    _controller.addListener(_refresh);
    _controller.initialize();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    if (_ownsController) _controller.dispose();
    _keyField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = _controller.configured;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Color(0xFFEAF4F0),
              child: Icon(Icons.auto_awesome_rounded, color: Color(0xFF0D6B57)),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الذكاء الاصطناعي', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  Text('Gemini Provider • مفتاح محلي مشفّر', style: TextStyle(color: Color(0xFF68736D))),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Gemini API Key', style: TextStyle(fontWeight: FontWeight.w800))),
                    _StatusChip(
                      label: _controller.connected
                          ? 'متصل'
                          : configured
                              ? 'محفوظ'
                              : 'غير مُعد',
                      positive: _controller.connected,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'لا يُحفظ المفتاح في SQLite أو GitHub ولا يُعرض بعد الحفظ. يُستخدم فقط عند إرسال طلب مباشر إلى Gemini.',
                  style: TextStyle(color: Color(0xFF68736D), height: 1.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('gemini-api-key-field'),
                  controller: _keyField,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: configured ? 'أدخل مفتاحًا جديدًا لاستبدال الحالي' : 'ألصق API Key هنا',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('gemini-save-key'),
                      onPressed: _controller.loading
                          ? null
                          : () async {
                              await _controller.save(_keyField.text);
                              if (_controller.configured) _keyField.clear();
                            },
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: const Text('حفظ بأمان'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('gemini-test-connection'),
                      onPressed: _controller.loading || !configured ? null : _controller.testConnection,
                      icon: const Icon(Icons.wifi_tethering_rounded),
                      label: const Text('اختبار الاتصال'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('gemini-delete-key'),
                      onPressed: _controller.loading || !configured ? null : _controller.delete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('حذف المفتاح'),
                    ),
                  ],
                ),
                if (_controller.loading) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                ],
                if (_controller.message != null) ...[
                  const SizedBox(height: 14),
                  Text(_controller.message!, style: const TextStyle(height: 1.5)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Card(
          elevation: 0,
          child: ListTile(
            leading: Icon(Icons.security_rounded, color: Color(0xFF0D6B57)),
            title: Text('حدود الأمان'),
            subtitle: Text(
              'Gemini لا يملك وصولًا مباشرًا لقاعدة IBEX ولا ينفذ SQL. مخرجاته تمر عبر typed drafts والتحقق والموافقة قبل أي mutation.',
              style: TextStyle(height: 1.45),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.positive});
  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: positive ? const Color(0xFFEAF4F0) : const Color(0xFFF1F2F1),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
