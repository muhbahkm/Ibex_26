import 'dart:convert';

import 'package:crypto/crypto.dart';

class StableOperationId {
  const StableOperationId._();

  /// Builds a deterministic UUID-form identifier for one logical operation.
  /// The same canonical material always returns the same id, so a retry after
  /// an uncertain commit boundary cannot accidentally create a second truth.
  static String fromCanonicalMaterial(String material) {
    final normalized = material.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(material, 'material', 'Operation id material cannot be blank.');
    }

    final digest = sha256.convert(utf8.encode(normalized)).bytes;
    final bytes = List<int>.of(digest.take(16));

    // UUID-compatible layout: mark the deterministic hash-derived identifier
    // as version 5 and RFC 4122 variant. This is used as an idempotency key,
    // not as a claim that SHA-1 UUIDv5 namespace generation was performed.
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  static String forApprovedDraft({
    required String commandName,
    required String businessId,
    required String draftId,
    required int version,
    required String fingerprint,
  }) {
    final command = commandName.trim();
    final business = businessId.trim();
    final draft = draftId.trim();
    final approvedFingerprint = fingerprint.trim();
    if (command.isEmpty || business.isEmpty || draft.isEmpty || approvedFingerprint.isEmpty) {
      throw ArgumentError('Approved draft operation material cannot contain blank identity fields.');
    }
    if (version <= 0) {
      throw ArgumentError.value(version, 'version', 'Draft version must be positive.');
    }
    return fromCanonicalMaterial(
      'IBEX2|$command|business=$business|draft=$draft|version=$version|fingerprint=$approvedFingerprint',
    );
  }

  static String forApprovedSaleDraft({
    required String businessId,
    required String draftId,
    required int version,
    required String fingerprint,
  }) =>
      forApprovedDraft(
        commandName: 'PostSale',
        businessId: businessId,
        draftId: draftId,
        version: version,
        fingerprint: fingerprint,
      );
}
