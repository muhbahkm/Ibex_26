class DomainError implements Exception {
  const DomainError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'DomainError($code): $message';
}
