import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/agent/operational_draft.dart';
import 'package:ibex_foundation_spike/presentation/sale_chat_controller.dart';

void main() {
  test('demo controller creates a real operational draft and exposes view data', () async {
    final controller = SaleChatController.demo();
    addTearDown(controller.dispose);

    await controller.initializeDemoDraft();

    expect(controller.draft, isNotNull);
    expect(controller.draft!.state, OperationalDraftState.awaitingApproval);
    expect(controller.viewData!.customerName, 'محمد عبدالله باحكم');
    expect(controller.viewData!.unitPriceText, '500');
    expect(controller.viewData!.totalText, '500');
  });

  test('natural-language price revision creates a new draft version and invalidates approval', () async {
    final controller = SaleChatController.demo();
    addTearDown(controller.dispose);
    await controller.initializeDemoDraft();
    controller.approve();
    expect(controller.draft!.state, OperationalDraftState.approved);

    controller.submitNaturalLanguage('اجعل المبلغ 400');

    expect(controller.draft!.version, 2);
    expect(controller.draft!.state, OperationalDraftState.awaitingApproval);
    expect(controller.draft!.approvedFingerprint, isNull);
    expect(controller.viewData!.unitPriceText, '400');
    expect(controller.messages.last.text, contains('تحتاج المسودة إلى مراجعة جديدة'));
  });

  test('ambiguous numeric conversational revision is not guessed', () async {
    final controller = SaleChatController.demo();
    addTearDown(controller.dispose);
    await controller.initializeDemoDraft();

    controller.submitNaturalLanguage('اجعل السعر بين 400 و 500');

    expect(controller.draft!.version, 1);
    expect(controller.viewData!.unitPriceText, '500');
    expect(controller.messages.last.text, contains('لا أنفذ إلا أوامر تعديل السعر المحددة'));
  });
}
