import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/encrypted_database_opener.dart';
import '../database/spike_database.dart';
import '../security/secure_database_key_store.dart';
import 'local_business_bootstrap_service.dart';

class ProductionBootstrapGateway {
  const ProductionBootstrapGateway();

  Future<void> bootstrap(LocalBusinessBootstrapRequest request) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'ibex2-local.db'));
    final key = await SecureDatabaseKeyStore().loadOrCreateHexKey();
    final db = SpikeDatabase(
      EncryptedDatabaseOpener.open(file: file, hexKey: key),
    );
    try {
      await LocalBusinessBootstrapService(db).execute(request);
    } finally {
      await db.close();
    }
  }
}
