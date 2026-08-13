import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/core/id/stable_operation_id.dart';

void main() {
  test('same approved sale draft material returns the same UUID-form operation id', () {
    final first = StableOperationId.forApprovedSaleDraft(
      businessId: 'B-1',
      draftId: 'draft-sale-1',
      version: 3,
      fingerprint: 'abc123',
    );
    final retry = StableOperationId.forApprovedSaleDraft(
      businessId: 'B-1',
      draftId: 'draft-sale-1',
      version: 3,
      fingerprint: 'abc123',
    );

    expect(retry, first);
    expect(
      first,
      matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )),
    );
  });

  test('material revision changes the deterministic operation id', () {
    final v1 = StableOperationId.forApprovedSaleDraft(
      businessId: 'B-1',
      draftId: 'draft-sale-1',
      version: 1,
      fingerprint: 'fingerprint-v1',
    );
    final v2 = StableOperationId.forApprovedSaleDraft(
      businessId: 'B-1',
      draftId: 'draft-sale-1',
      version: 2,
      fingerprint: 'fingerprint-v2',
    );

    expect(v2, isNot(v1));
  });

  test('blank canonical material is rejected', () {
    expect(
      () => StableOperationId.fromCanonicalMaterial('   '),
      throwsArgumentError,
    );
  });
}
