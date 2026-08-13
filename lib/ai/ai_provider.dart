abstract interface class AiProvider {
  String get providerId;
  Future<AiProviderHealth> testConnection();
}

class AiProviderHealth {
  const AiProviderHealth({required this.ok, required this.message});
  final bool ok;
  final String message;
}
