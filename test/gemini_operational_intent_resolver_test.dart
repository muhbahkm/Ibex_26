import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/ai/gemini_api_key_store.dart';
import 'package:ibex_foundation_spike/ai/gemini_operational_intent_resolver.dart';
import 'package:ibex_foundation_spike/ai/operational_ai_intent.dart';

void main() {
  test('returns null and never calls transport when no API key exists', () async {
    final transport = _FakeTransport(_response({'action': 'unknown'}));
    final resolver = GeminiOperationalIntentResolver(
      keyStore: _MemoryKeyStore(null),
      transport: transport,
    );

    expect(await resolver.resolve('أي طلب'), isNull);
    expect(transport.calls, 0);
  });

  test('accepts a complete structured create-sale intent', () async {
    final resolver = GeminiOperationalIntentResolver(
      keyStore: _MemoryKeyStore('abcdefghijklmnopqrstuvwxyz123456'),
      transport: _FakeTransport(
        _response({
          'action': 'create_sale',
          'customer': 'محمد عبدالله باحكم',
          'product': 'سدر عبوة كيلو',
          'unit': 'جالون',
          'quantity': '1',
          'unit_price': '500',
          'currency': 'SAR',
          'settlement_mode': 'credit',
        }),
      ),
    );

    final intent = await resolver.resolve('سجل لمحمد سدر على الحساب');
    expect(intent, isNotNull);
    expect(intent!.action, AiOperationalAction.createSale);
    expect(intent.argument('customer'), 'محمد عبدالله باحكم');
    expect(intent.argument('settlement_mode'), 'credit');
  });

  test('fails closed when Gemini omits required sale arguments', () async {
    final resolver = GeminiOperationalIntentResolver(
      keyStore: _MemoryKeyStore('abcdefghijklmnopqrstuvwxyz123456'),
      transport: _FakeTransport(
        _response({
          'action': 'create_sale',
          'customer': 'محمد',
          'product': 'سدر',
        }),
      ),
    );

    final intent = await resolver.resolve('بيع لمحمد سدر');
    expect(intent, isNotNull);
    expect(intent!.action, AiOperationalAction.unknown);
    expect(intent.arguments, isEmpty);
  });

  test('ignores unregistered fields instead of forwarding arbitrary payload', () async {
    final resolver = GeminiOperationalIntentResolver(
      keyStore: _MemoryKeyStore('abcdefghijklmnopqrstuvwxyz123456'),
      transport: _FakeTransport(
        _response({
          'action': 'customer_balance',
          'customer': 'محمد',
          'sql': 'DROP TABLE sales',
          'operation_id': 'evil',
        }),
      ),
    );

    final intent = await resolver.resolve('كم رصيد محمد');
    expect(intent!.action, AiOperationalAction.customerBalance);
    expect(intent.arguments, {'customer': 'محمد'});
  });
}

String _response(Map<String, Object?> structured) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(structured)}
            ]
          }
        }
      ]
    });

class _FakeTransport implements GeminiIntentTransport {
  _FakeTransport(this.body);
  final String body;
  int calls = 0;

  @override
  Future<GeminiIntentHttpResult> generate({
    required String apiKey,
    required String userText,
  }) async {
    calls += 1;
    return GeminiIntentHttpResult(statusCode: 200, body: body);
  }
}

class _MemoryKeyStore implements GeminiApiKeyStore {
  _MemoryKeyStore(this.value);
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<bool> hasKey() async => value?.isNotEmpty == true;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> save(String apiKey) async => value = apiKey;
}
