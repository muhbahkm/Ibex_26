import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/command_registry.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/core/errors/domain_error.dart';

void main() {
  group('Conversational Operating Agent contract', () {
    test('approval binds to exact immutable draft version and payload', () {
      final draft = OperationalDraft(
        draftId: 'draft-sale-1',
        commandName: 'PostSale',
        version: 1,
        payload: const {
          'customer_id': 'C-1',
          'currency': 'SAR',
          'lines': [
            {
              'product_id': 'P-SIDR',
              'unit_id': 'U-GALLON',
              'quantity_scaled': 1000000,
              'unit_price_scaled': 5000000,
            },
          ],
        },
        state: OperationalDraftState.draftReady,
        createdAtUtc: DateTime.utc(2026, 8, 11),
      );

      final approved = draft.markAwaitingApproval().approve();
      expect(approved.approvedFingerprint, approved.fingerprint);
      expect(() => approved.requireValidApprovalForPosting(), returnsNormally);
    });

    test('material revision invalidates prior approval and requires new preview', () {
      final approved = OperationalDraft(
        draftId: 'draft-sale-2',
        commandName: 'PostSale',
        version: 1,
        payload: const {
          'customer_id': 'C-1',
          'currency': 'SAR',
          'total_scaled': 5000000,
        },
        state: OperationalDraftState.draftReady,
        createdAtUtc: DateTime.utc(2026, 8, 11),
      ).markAwaitingApproval().approve();

      final revised = approved.revise(const {
        'customer_id': 'C-1',
        'currency': 'SAR',
        'total_scaled': 6000000,
      });

      expect(revised.version, 2);
      expect(revised.state, OperationalDraftState.draftReady);
      expect(revised.approvedFingerprint, isNull);
      expect(
        () => revised.requireValidApprovalForPosting(),
        throwsA(isA<DomainError>()),
      );
    });

    test('cancelled and expired drafts cannot post', () {
      final base = OperationalDraft(
        draftId: 'draft-sale-3',
        commandName: 'PostSale',
        version: 1,
        payload: const {'customer_id': 'C-1'},
        state: OperationalDraftState.draftReady,
        createdAtUtc: DateTime.utc(2026, 8, 11),
      );

      expect(
        () => base.cancel().requireValidApprovalForPosting(),
        throwsA(isA<DomainError>()),
      );
      expect(
        () => base.expire().requireValidApprovalForPosting(),
        throwsA(isA<DomainError>()),
      );
    });

    test('same semantic payload produces stable fingerprint regardless of map key order', () {
      final a = OperationalDraft(
        draftId: 'draft-stable',
        commandName: 'PostSale',
        version: 1,
        payload: const {'currency': 'SAR', 'customer_id': 'C-1'},
        state: OperationalDraftState.draftReady,
        createdAtUtc: DateTime.utc(2026, 8, 11),
      );
      final b = OperationalDraft(
        draftId: 'draft-stable',
        commandName: 'PostSale',
        version: 1,
        payload: const {'customer_id': 'C-1', 'currency': 'SAR'},
        state: OperationalDraftState.draftReady,
        createdAtUtc: DateTime.utc(2026, 8, 11),
      );

      expect(a.fingerprint, b.fingerprint);
    });

    test('agent cannot invoke an unregistered command', () {
      const registry = AgentCommandRegistry({'CreateSaleDraft', 'PostSale'});
      expect(() => registry.requireRegistered('PostSale'), returnsNormally);
      expect(
        () => registry.requireRegistered('DELETE FROM sales'),
        throwsA(isA<DomainError>()),
      );
    });
  });
}
