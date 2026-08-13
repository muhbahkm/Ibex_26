import 'package:flutter/foundation.dart';

import 'ai_provider.dart';
import 'gemini_api_key_store.dart';

class GeminiSettingsController extends ChangeNotifier {
  GeminiSettingsController({required GeminiApiKeyStore keyStore, required AiProvider provider})
      : _keyStore = keyStore,
        _provider = provider;

  final GeminiApiKeyStore _keyStore;
  final AiProvider _provider;

  bool _loading = false;
  bool _configured = false;
  bool _connected = false;
  String? _message;

  bool get loading => _loading;
  bool get configured => _configured;
  bool get connected => _connected;
  String? get message => _message;

  Future<void> initialize() async {
    _configured = await _keyStore.hasKey();
    _connected = false;
    _message = null;
    notifyListeners();
  }

  Future<void> save(String apiKey) async {
    _loading = true;
    _message = null;
    notifyListeners();
    try {
      await _keyStore.save(apiKey);
      _configured = true;
      _connected = false;
      _message = 'تم حفظ المفتاح بأمان على هذا الجهاز.';
    } catch (_) {
      _message = 'تعذر حفظ المفتاح. تحقق من القيمة وأعد المحاولة.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> testConnection() async {
    _loading = true;
    _message = null;
    notifyListeners();
    try {
      final health = await _provider.testConnection();
      _connected = health.ok;
      _configured = await _keyStore.hasKey();
      _message = health.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> delete() async {
    _loading = true;
    notifyListeners();
    try {
      await _keyStore.delete();
      _configured = false;
      _connected = false;
      _message = 'تم حذف مفتاح Gemini من هذا الجهاز.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
