import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureDatabaseKeyStore {
  SecureDatabaseKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'ibex2.database.hex_key.v1';
  final FlutterSecureStorage _storage;

  Future<String> loadOrCreateHexKey() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null) {
      _validateHexKey(existing);
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    _validateHexKey(key);
    await _storage.write(key: _storageKey, value: key);
    return key;
  }

  Future<String?> readHexKey() async {
    final value = await _storage.read(key: _storageKey);
    if (value != null) _validateHexKey(value);
    return value;
  }

  Future<void> deleteKeyForSpikeTestOnly() => _storage.delete(key: _storageKey);

  void _validateHexKey(String value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw StateError('Stored IBEX database key is not a valid 256-bit lowercase hex key.');
    }
  }
}
