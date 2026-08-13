import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/errors/domain_error.dart';

enum OperationalDraftState {
  draftReady,
  awaitingApproval,
  approved,
  cancelled,
  expired,
  posted,
}

class OperationalDraft {
  const OperationalDraft({
    required this.draftId,
    required this.commandName,
    required this.version,
    required this.payload,
    required this.state,
    required this.createdAtUtc,
    this.approvedFingerprint,
  });

  final String draftId;
  final String commandName;
  final int version;
  final Map<String, Object?> payload;
  final OperationalDraftState state;
  final DateTime createdAtUtc;
  final String? approvedFingerprint;

  String get fingerprint {
    final canonical = _canonicalize({
      'draft_id': draftId,
      'command_name': commandName,
      'version': version,
      'payload': payload,
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  OperationalDraft markAwaitingApproval() {
    _requireMutable();
    return _copy(state: OperationalDraftState.awaitingApproval);
  }

  OperationalDraft approve() {
    if (state != OperationalDraftState.awaitingApproval) {
      throw const DomainError(
        'DRAFT_NOT_AWAITING_APPROVAL',
        'Draft must be awaiting approval before it can be approved.',
      );
    }
    return _copy(
      state: OperationalDraftState.approved,
      approvedFingerprint: fingerprint,
    );
  }

  OperationalDraft revise(Map<String, Object?> nextPayload) {
    _requireMutable();
    return OperationalDraft(
      draftId: draftId,
      commandName: commandName,
      version: version + 1,
      payload: Map.unmodifiable(nextPayload),
      state: OperationalDraftState.draftReady,
      createdAtUtc: createdAtUtc,
      approvedFingerprint: null,
    );
  }

  OperationalDraft cancel() {
    if (state == OperationalDraftState.posted ||
        state == OperationalDraftState.expired) {
      throw const DomainError(
        'DRAFT_TERMINAL_STATE',
        'Draft is already in a terminal state.',
      );
    }
    return _copy(
      state: OperationalDraftState.cancelled,
      approvedFingerprint: null,
    );
  }

  OperationalDraft expire() {
    if (state == OperationalDraftState.posted ||
        state == OperationalDraftState.cancelled) {
      throw const DomainError(
        'DRAFT_TERMINAL_STATE',
        'Draft is already in a terminal state.',
      );
    }
    return _copy(
      state: OperationalDraftState.expired,
      approvedFingerprint: null,
    );
  }

  void requireValidApprovalForPosting() {
    if (state != OperationalDraftState.approved) {
      throw const DomainError(
        'DRAFT_APPROVAL_REQUIRED',
        'Draft must be approved before posting.',
      );
    }
    if (approvedFingerprint != fingerprint) {
      throw const DomainError(
        'DRAFT_APPROVAL_STALE',
        'Draft approval no longer matches the current draft version.',
      );
    }
  }

  OperationalDraft markPosted() {
    requireValidApprovalForPosting();
    return _copy(state: OperationalDraftState.posted);
  }

  OperationalDraft _copy({
    OperationalDraftState? state,
    String? approvedFingerprint,
  }) {
    return OperationalDraft(
      draftId: draftId,
      commandName: commandName,
      version: version,
      payload: payload,
      state: state ?? this.state,
      createdAtUtc: createdAtUtc,
      approvedFingerprint: approvedFingerprint,
    );
  }

  void _requireMutable() {
    if (state == OperationalDraftState.cancelled ||
        state == OperationalDraftState.expired ||
        state == OperationalDraftState.posted) {
      throw const DomainError(
        'DRAFT_TERMINAL_STATE',
        'Draft cannot be changed in its current state.',
      );
    }
  }
}

String _canonicalize(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return jsonEncode(value);
  }
  if (value is List) {
    return '[${value.map(_canonicalize).join(',')}]';
  }
  if (value is Map) {
    final entries = value.entries
        .map((entry) => MapEntry(entry.key.toString(), entry.value))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '{${entries.map((e) => '${jsonEncode(e.key)}:${_canonicalize(e.value)}').join(',')}}';
  }
  throw ArgumentError.value(value, 'value', 'Unsupported draft payload value.');
}
