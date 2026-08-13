import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_provider.dart';
import 'gemini_api_key_store.dart';

abstract interface class GeminiTransport {
  Future<GeminiHttpResult> getModels(String apiKey);
}

class GeminiHttpResult {
  const GeminiHttpResult({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

class IoGeminiTransport implements GeminiTransport {
  const IoGeminiTransport();

  @override
  Future<GeminiHttpResult> getModels(String apiKey) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1'),
      );
      request.headers.set('x-goog-api-key', apiKey);
      request.headers.set('x-goog-api-client', 'ibex-android/2.0');
      final response = await request.close().timeout(const Duration(seconds: 12));
      final body = await utf8.decoder.bind(response).join();
      return GeminiHttpResult(statusCode: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }
}

class GeminiProvider implements AiProvider {
  GeminiProvider({
    required GeminiApiKeyStore keyStore,
    GeminiTransport transport = const IoGeminiTransport(),
  })  : _keyStore = keyStore,
        _transport = transport;

  final GeminiApiKeyStore _keyStore;
  final GeminiTransport _transport;

  @override
  String get providerId => 'gemini';

  @override
  Future<AiProviderHealth> testConnection() async {
    final key = await _keyStore.read();
    if (key == null || key.trim().isEmpty) {
      return const AiProviderHealth(ok: false, message: 'لم يتم حفظ مفتاح Gemini بعد.');
    }

    try {
      final result = await _transport.getModels(key);
      if (result.statusCode >= 200 && result.statusCode < 300) {
        return const AiProviderHealth(ok: true, message: 'تم الاتصال بـ Gemini بنجاح.');
      }
      if (result.statusCode == 400 || result.statusCode == 401 || result.statusCode == 403) {
        return const AiProviderHealth(ok: false, message: 'رفض Gemini المفتاح. تحقق من API Key وصلاحياته.');
      }
      return AiProviderHealth(
        ok: false,
        message: 'تعذر الاتصال بـ Gemini (HTTP ${result.statusCode}).',
      );
    } on SocketException {
      return const AiProviderHealth(ok: false, message: 'لا يوجد اتصال بالإنترنت لاختبار Gemini.');
    } on TimeoutException {
      return const AiProviderHealth(ok: false, message: 'انتهت مهلة الاتصال بـ Gemini.');
    } catch (_) {
      return const AiProviderHealth(ok: false, message: 'تعذر اختبار Gemini بأمان.');
    }
  }
}
