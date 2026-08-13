import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class LocalInstallationIdentity {
  const LocalInstallationIdentity({
    required this.businessId,
    required this.ownerUserId,
  });

  final String businessId;
  final String ownerUserId;
}

class LocalInstallationIdentityStore {
  LocalInstallationIdentityStore({
    FlutterSecureStorage? storage,
    Uuid? uuid,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _uuid = uuid ?? const Uuid();

  static const _businessKey = 'ibex2.installation.business_id.v1';
  static const _ownerKey = 'ibex2.installation.owner_user_id.v1';

  final FlutterSecureStorage _storage;
  final Uuid _uuid;

  Future<LocalInstallationIdentity> loadOrCreate() async {
    var businessId = await _storage.read(key: _businessKey);
    var ownerUserId = await _storage.read(key: _ownerKey);

    businessId = _validId(businessId) ? businessId : 'B-${_uuid.v4()}';
    ownerUserId = _validId(ownerUserId) ? ownerUserId : 'U-${_uuid.v4()}';

    await _storage.write(key: _businessKey, value: businessId);
    await _storage.write(key: _ownerKey, value: ownerUserId);
    return LocalInstallationIdentity(
      businessId: businessId,
      ownerUserId: ownerUserId,
    );
  }

  bool _validId(String? value) =>
      value != null && value.length >= 8 && !value.contains(RegExp(r'\s'));
}
