import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class GeminiApiKeyStore {
  Future<bool> hasKey();
  Future<void> save(String apiKey);
  Future<String?> read();
  Future<void> delete();
}

class SecureGeminiApiKeyStore implements GeminiApiKeyStore {
  SecureGeminiApiKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'ibex2.ai.gemini.api_key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<bool> hasKey() async {
    final value = await _storage.read(key: _storageKey);
    return value != null && value.trim().isNotEmpty;
  }

  @override
  Future<void> save(String apiKey) async {
    final value = apiKey.trim();
    if (value.length < 20) {
      throw ArgumentError('Gemini API key is too short.');
    }
    await _storage.write(key: _storageKey, value: value);
  }

  @override
  Future<String?> read() => _storage.read(key: _storageKey);

  @override
  Future<void> delete() => _storage.delete(key: _storageKey);
}
