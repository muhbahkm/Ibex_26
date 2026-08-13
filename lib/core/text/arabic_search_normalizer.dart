class ArabicSearchNormalizer {
  const ArabicSearchNormalizer._();

  static String normalize(String input) {
    var value = input.trim().toLowerCase();
    value = value
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('\u0640', '')
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه');
    value = value.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
