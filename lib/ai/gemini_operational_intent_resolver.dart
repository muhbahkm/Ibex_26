import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'gemini_api_key_store.dart';
import 'operational_ai_intent.dart';

abstract interface class GeminiIntentTransport {
  Future<GeminiIntentHttpResult> generate({
    required String apiKey,
    required String userText,
  });
}

class GeminiIntentHttpResult {
  const GeminiIntentHttpResult({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

class IoGeminiIntentTransport implements GeminiIntentTransport {
  const IoGeminiIntentTransport({this.model = 'gemini-2.5-flash'});

  final String model;

  @override
  Future<GeminiIntentHttpResult> generate({
    required String apiKey,
    required String userText,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
        ),
      );
      request.headers.set('x-goog-api-key', apiKey);
      request.headers.contentType = ContentType.json;
      request.headers.set('x-goog-api-client', 'ibex-android/2.0');

      final payload = <String, Object?>{
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text': '''
أنت مفسر أوامر فقط لنظام IBEX المحلي. لا تنفذ أي عملية، لا تكتب SQL، ولا تخترع بيانات.
صنّف طلب المستخدم إلى أحد الأفعال المحددة في مخطط JSON فقط.
إذا كانت البيانات ناقصة أو غير واضحة اختر unknown.
طلب المستخدم:
$userText
''',
              }
            ],
          }
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'responseSchema': {
            'type': 'OBJECT',
            'properties': {
              'action': {
                'type': 'STRING',
                'enum': [
                  'create_sale',
                  'customer_balance',
                  'inventory_balance',
                  'supplier_balance',
                  'unknown',
                ],
              },
              'customer': {'type': 'STRING'},
              'product': {'type': 'STRING'},
              'unit': {'type': 'STRING'},
              'quantity': {'type': 'STRING'},
              'unit_price': {'type': 'STRING'},
              'currency': {'type': 'STRING'},
              'settlement_mode': {
                'type': 'STRING',
                'enum': ['cash', 'credit', ''],
              },
              'supplier': {'type': 'STRING'},
            },
            'required': ['action'],
          },
        },
      };
      request.write(jsonEncode(payload));
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decoder.bind(response).join();
      return GeminiIntentHttpResult(statusCode: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }
}

class GeminiOperationalIntentResolver implements OperationalAiIntentResolver {
  GeminiOperationalIntentResolver({
    required GeminiApiKeyStore keyStore,
    GeminiIntentTransport transport = const IoGeminiIntentTransport(),
  })  : _keyStore = keyStore,
        _transport = transport;

  final GeminiApiKeyStore _keyStore;
  final GeminiIntentTransport _transport;

  @override
  Future<AiOperationalIntent?> resolve(String userText) async {
    final value = userText.trim();
    if (value.isEmpty) return null;
    final key = await _keyStore.read();
    if (key == null || key.trim().isEmpty) return null;

    try {
      final result = await _transport.generate(apiKey: key, userText: value);
      if (result.statusCode < 200 || result.statusCode >= 300) return null;
      final envelope = jsonDecode(result.body);
      if (envelope is! Map<String, dynamic>) return null;
      final candidates = envelope['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final part = parts.first;
      if (part is! Map<String, dynamic>) return null;
      final text = part['text'];
      if (text is! String) return null;
      return _parseStructured(text);
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  AiOperationalIntent? _parseStructured(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) return null;
    final rawAction = decoded['action'];
    if (rawAction is! String) return null;

    final action = switch (rawAction) {
      'create_sale' => AiOperationalAction.createSale,
      'customer_balance' => AiOperationalAction.customerBalance,
      'inventory_balance' => AiOperationalAction.inventoryBalance,
      'supplier_balance' => AiOperationalAction.supplierBalance,
      _ => AiOperationalAction.unknown,
    };

    const allowed = {
      'customer',
      'product',
      'unit',
      'quantity',
      'unit_price',
      'currency',
      'settlement_mode',
      'supplier',
    };
    final args = <String, String>{};
    for (final entry in decoded.entries) {
      if (!allowed.contains(entry.key)) continue;
      final v = entry.value;
      if (v is String && v.trim().isNotEmpty) args[entry.key] = v.trim();
    }

    if (!_valid(action, args)) {
      return const AiOperationalIntent(
        action: AiOperationalAction.unknown,
        arguments: {},
      );
    }
    return AiOperationalIntent(action: action, arguments: args);
  }

  bool _valid(AiOperationalAction action, Map<String, String> args) {
    switch (action) {
      case AiOperationalAction.createSale:
        return _hasAll(args, const [
              'customer',
              'product',
              'unit',
              'quantity',
              'unit_price',
              'currency',
            ]) &&
            (!args.containsKey('settlement_mode') ||
                args['settlement_mode'] == 'cash' ||
                args['settlement_mode'] == 'credit');
      case AiOperationalAction.customerBalance:
        return _hasAll(args, const ['customer']);
      case AiOperationalAction.inventoryBalance:
        return _hasAll(args, const ['product']);
      case AiOperationalAction.supplierBalance:
        return _hasAll(args, const ['supplier']);
      case AiOperationalAction.unknown:
        return true;
    }
  }

  bool _hasAll(Map<String, String> args, List<String> keys) =>
      keys.every((key) => args[key]?.trim().isNotEmpty == true);
}
