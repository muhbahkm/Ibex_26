import 'dart:io';

import 'package:drift/native.dart';

class EncryptedDatabaseOpener {
  const EncryptedDatabaseOpener._();

  static NativeDatabase open({
    required File file,
    required String hexKey,
  }) {
    _validateHexKey(hexKey);
    return NativeDatabase(
      file,
      setup: (rawDb) {
        // SQLite3MultipleCiphers requires the key before any other SQL statement.
        rawDb.execute("PRAGMA hexkey = '$hexKey';");
        // Force key validation immediately. A wrong key must fail here instead of
        // surfacing later during an unrelated domain operation.
        rawDb.select('SELECT count(*) FROM sqlite_master;');
        rawDb.execute('PRAGMA foreign_keys = ON;');
      },
    );
  }

  static void _validateHexKey(String value) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'hexKey',
        'Encryption key must be exactly 32 bytes represented by 64 hexadecimal characters.',
      );
    }
  }
}
