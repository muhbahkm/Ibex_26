import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/agent/operational_draft_repository.dart';
import 'package:ibex_foundation_spike/database/spike_database.dart';

OperationalDraft _draft() => OperationalDraft(
      draftId: 'draft-persist-1',
      commandName: 'CreateSaleDraft',
      version: 1,
      payload: const {
        'customer_id': 'customer-1',
        'currency_code': 'SAR',
        'warehouse_id': 'warehouse-main',
        'lines': [
          {
            'product_id': 'product-1',
            'quantity_scaled': 1000000,
            'quantity_precision': 0,
            'unit_price_scaled': 5000000,
          }
        ],
      },
      state: OperationalDraftState.draftReady,
      createdAtUtc: DateTime.utc(2026, 8, 11, 10),
    ).markAwaitingApproval();

void main() {
  test('operational draft round-trips through local SQLite', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final repository = OperationalDraftRepository(db);

    final original = _draft();
    await repository.save(original);
    final loaded = await repository.load(original.draftId);

    expect(loaded, isNotNull);
    expect(loaded!.draftId, original.draftId);
    expect(loaded.commandName, original.commandName);
    expect(loaded.version, original.version);
    expect(loaded.state, OperationalDraftState.awaitingApproval);
    expect(loaded.fingerprint, original.fingerprint);
  });

  test('approved fingerprint survives persistence and remains valid', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final repository = OperationalDraftRepository(db);

    final approved = _draft().approve();
    await repository.save(approved);
    final loaded = await repository.load(approved.draftId);

    expect(loaded!.state, OperationalDraftState.approved);
    expect(loaded.approvedFingerprint, approved.fingerprint);
    expect(() => loaded.requireValidApprovalForPosting(), returnsNormally);
  });

  test('material revision overwrites stored draft with a new unapproved version', () async {
    final db = SpikeDatabase.inMemory();
    addTearDown(db.close);
    final repository = OperationalDraftRepository(db);

    final approved = _draft().approve();
    await repository.save(approved);
    final revised = approved.revise({
      ...approved.payload,
      'currency_code': 'USD',
    }).markAwaitingApproval();
    await repository.save(revised);

    final loaded = await repository.load(revised.draftId);
    expect(loaded!.version, 2);
    expect(loaded.state, OperationalDraftState.awaitingApproval);
    expect(loaded.approvedFingerprint, isNull);
    expect(loaded.payload['currency_code'], 'USD');
  });
}
