import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/errors/domain_error.dart';
import '../database/spike_database.dart';
import 'operational_draft.dart';

class OperationalDraftRepository {
  const OperationalDraftRepository(this.db);

  final SpikeDatabase db;

  Future<void> save(OperationalDraft draft) async {
    final payloadJson = jsonEncode(draft.payload);
    await db.customInsert(
      '''
      INSERT INTO operational_draft_records (
        draft_id, command_name, version, payload_json, state,
        created_at_utc, approved_fingerprint, updated_at_utc
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(draft_id) DO UPDATE SET
        command_name = excluded.command_name,
        version = excluded.version,
        payload_json = excluded.payload_json,
        state = excluded.state,
        created_at_utc = excluded.created_at_utc,
        approved_fingerprint = excluded.approved_fingerprint,
        updated_at_utc = excluded.updated_at_utc
      ''',
      variables: [
        Variable.withString(draft.draftId),
        Variable.withString(draft.commandName),
        Variable.withInt(draft.version),
        Variable.withString(payloadJson),
        Variable.withString(draft.state.name),
        Variable.withString(draft.createdAtUtc.toUtc().toIso8601String()),
        Variable<String>(draft.approvedFingerprint),
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
      ],
      updates: {db.operationalDraftRecords},
    );
  }

  Future<OperationalDraft?> load(String draftId) async {
    final rows = await db.customSelect(
      '''
      SELECT draft_id, command_name, version, payload_json, state,
             created_at_utc, approved_fingerprint
      FROM operational_draft_records
      WHERE draft_id = ?
      LIMIT 1
      ''',
      variables: [Variable.withString(draftId)],
      readsFrom: {db.operationalDraftRecords},
    ).get();
    return rows.isEmpty ? null : _decode(rows.single);
  }

  Future<OperationalDraft?> loadLatestOpen({String? commandName}) async {
    final whereCommand = commandName == null ? '' : 'AND command_name = ?';
    final variables = <Variable<Object>>[
      const Variable<String>('cancelled'),
      const Variable<String>('expired'),
      const Variable<String>('posted'),
      if (commandName != null) Variable.withString(commandName),
    ];
    final rows = await db.customSelect(
      '''
      SELECT draft_id, command_name, version, payload_json, state,
             created_at_utc, approved_fingerprint
      FROM operational_draft_records
      WHERE state NOT IN (?, ?, ?) $whereCommand
      ORDER BY updated_at_utc DESC
      LIMIT 1
      ''',
      variables: variables,
      readsFrom: {db.operationalDraftRecords},
    ).get();
    return rows.isEmpty ? null : _decode(rows.single);
  }

  OperationalDraft _decode(QueryRow row) {
    final payloadRaw = row.read<String>('payload_json');
    final decoded = jsonDecode(payloadRaw);
    if (decoded is! Map) {
      throw const DomainError(
        'DRAFT_STORAGE_CORRUPT',
        'Stored operational draft payload is invalid.',
      );
    }
    final payload = <String, Object?>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    };
    final stateName = row.read<String>('state');
    final state = OperationalDraftState.values.where((value) => value.name == stateName).firstOrNull;
    if (state == null) {
      throw const DomainError(
        'DRAFT_STORAGE_CORRUPT',
        'Stored operational draft state is invalid.',
      );
    }

    final draft = OperationalDraft(
      draftId: row.read<String>('draft_id'),
      commandName: row.read<String>('command_name'),
      version: row.read<int>('version'),
      payload: Map.unmodifiable(payload),
      state: state,
      createdAtUtc: DateTime.parse(row.read<String>('created_at_utc')).toUtc(),
      approvedFingerprint: row.readNullable<String>('approved_fingerprint'),
    );

    if (state == OperationalDraftState.approved &&
        draft.approvedFingerprint != draft.fingerprint) {
      throw const DomainError(
        'DRAFT_STORAGE_APPROVAL_INVALID',
        'Stored draft approval does not match its persisted content.',
      );
    }
    return draft;
  }
}
