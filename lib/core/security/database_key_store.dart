import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class DatabaseKeyStore {
  Future<String> getOrCreateKey();
  Future<void> deleteKey();
}

class SecureDatabaseKeyStore implements DatabaseKeyStore {
  SecureDatabaseKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? FlutterSecureStorage(aOptions: AndroidOptions());

  static const _keyName = 'ibex_local_db_key_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String> getOrCreateKey() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final encoded = base64UrlEncode(bytes);
    await _storage.write(key: _keyName, value: encoded);
    return encoded;
  }

  @override
  Future<void> deleteKey() => _storage.delete(key: _keyName);
}
