import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibex_foundation_spike/ui/ibex_chat_shell.dart';

Future<void> _scrollConversationToBottom(WidgetTester tester) async {
  final scrollable = find.byKey(const ValueKey('ibex-conversation-scroll'));
  expect(scrollable, findsOneWidget);
  await tester.drag(scrollable, const Offset(0, -1200));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('chat-first shell renders a real Arabic RTL sale draft preview', (tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const IbexVisualApp());
    await tester.pumpAndSettle();

    expect(find.text('ماذا تريد أن تنجز اليوم؟'), findsOneWidget);
    expect(find.text('مسودة فاتورة بيع'), findsOneWidget);
    expect(find.text('محمد عبدالله باحكم'), findsOneWidget);
    expect(find.text('500 SAR'), findsOneWidget);
    expect(find.text('بانتظار الموافقة'), findsOneWidget);
    expect(find.byKey(const ValueKey('sale-draft-card')), findsOneWidget);

    final context = tester.element(find.byType(IbexChatShell));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  testWidgets('approval then material edit creates v2 and requires fresh approval', (tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const IbexVisualApp());
    await tester.pumpAndSettle();
    await _scrollConversationToBottom(tester);

    final approve = find.byKey(const ValueKey('approve-draft'));
    expect(approve, findsOneWidget);
    await tester.tap(approve, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('تمت الموافقة'), findsOneWidget);
    expect(find.text('موافق عليها'), findsOneWidget);

    final edit = find.byKey(const ValueKey('edit-draft'));
    await tester.tap(edit, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('الإصدار 2'), findsWidgets);
    expect(find.text('400 SAR'), findsOneWidget);
    expect(find.text('بانتظار الموافقة'), findsOneWidget);
    expect(find.text('اعتماد'), findsOneWidget);
  });

  testWidgets('natural-language price revision changes the operational draft without posting', (tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const IbexVisualApp());
    await tester.pumpAndSettle();

    const message = 'اجعل المبلغ 400';
    final composer = find.byKey(const ValueKey('ibex-composer'));
    await tester.enterText(composer, message);
    await tester.tap(find.byKey(const ValueKey('ibex-send')));
    await tester.pumpAndSettle();
    await _scrollConversationToBottom(tester);

    expect(find.text(message), findsOneWidget);
    expect(find.textContaining('عدّلت سعر المسودة إلى 400 SAR'), findsOneWidget);
    expect(find.textContaining('الإصدار 2'), findsWidgets);
    expect(find.text('400 SAR'), findsOneWidget);
    expect(find.text('بانتظار الموافقة'), findsOneWidget);
  });
}
