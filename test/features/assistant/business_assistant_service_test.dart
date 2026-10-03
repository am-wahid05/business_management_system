import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_2/features/assistant/business_assistant_screen.dart';
import 'package:flutter_application_2/features/assistant/business_assistant_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scriptable stand-in for the Edge Function.
///
/// The invoker is an interface precisely so these tests never touch Supabase or
/// an OpenAI key: the whole assistant is exercised through the same seam the
/// app uses.
class FakeAssistantInvoker implements AssistantInvoker {
  FakeAssistantInvoker(this.reply);

  final Future<AssistantAnswer> Function(String question) reply;

  final List<String> asked = [];
  int calls = 0;

  @override
  Future<AssistantAnswer> ask(String question) async {
    calls++;
    asked.add(question);
    return reply(question);
  }
}

Widget host(BusinessAssistantService service) => MaterialApp(
  home: BusinessAssistantScreen(service: service),
);

void main() {
  group('authentication and the wire contract', () {
    test('only the question is sent; the client never states a company', () {
      // The invoker receives a bare question string. There is deliberately no
      // parameter through which a caller could pass a company id or a role, so
      // the server is forced to resolve both from the signed-in user.
      final invoker = FakeAssistantInvoker(
        (_) async => const AssistantAnswer.answer('ok'),
      );
      BusinessAssistantService(invoker).answer('How much today?');

      expect(invoker.asked.single, 'How much today?');
    });

    test('a missing Supabase client cannot reach the assistant', () async {
      // A null client means the app has no remote project, so the assistant is
      // genuinely unreachable rather than silently answering from local data.
      final invoker = SupabaseAssistantInvoker(null);
      final answer = await invoker.ask('anything');

      expect(answer.offline, isTrue);
      expect(answer.text, AssistantAnswer.defaultOfflineMessage);
    });

    test('the friendly offline wording is the one the user is shown', () {
      expect(
        AssistantAnswer.defaultOfflineMessage,
        'AI Assistant requires an internet connection.',
      );
    });
  });

  group('input validation', () {
    test('a blank question is refused without calling the assistant', () async {
      final invoker = FakeAssistantInvoker(
        (_) async => const AssistantAnswer.answer('ok'),
      );
      final answer = await BusinessAssistantService(invoker).answer('   ');

      expect(invoker.calls, 0);
      expect(answer.text, contains('type a question'));
    });

    test('surrounding whitespace is trimmed before sending', () async {
      final invoker = FakeAssistantInvoker(
        (_) async => const AssistantAnswer.answer('ok'),
      );
      await BusinessAssistantService(invoker).answer('  total for today?  ');

      expect(invoker.asked.single, 'total for today?');
    });
  });

  group('duplicate request protection', () {
    test('a second question while one is in flight is not sent', () async {
      final gate = Completer<AssistantAnswer>();
      final invoker = FakeAssistantInvoker((_) => gate.future);
      final service = BusinessAssistantService(invoker);

      final first = service.answer('first question');
      // The screen's send button is disabled while working, but the guard also
      // lives in the service so a fast double tap cannot bill twice.
      final second = await service.answer('second question');

      expect(invoker.calls, 1);
      expect(second.text, contains('Still working'));

      gate.complete(const AssistantAnswer.answer('done'));
      expect((await first).text, 'done');
    });

    test('a new question is allowed once the previous one finished', () async {
      final invoker = FakeAssistantInvoker(
        (_) async => const AssistantAnswer.answer('done'),
      );
      final service = BusinessAssistantService(invoker);

      await service.answer('one');
      await service.answer('two');

      expect(invoker.calls, 2);
      expect(service.isBusy, isFalse);
    });

    test('isBusy clears even when the assistant fails', () async {
      final invoker = FakeAssistantInvoker(
        (_) async => const AssistantAnswer.offline(),
      );
      final service = BusinessAssistantService(invoker);

      await service.answer('anything');

      // A failure must not leave the service permanently refusing questions.
      expect(service.isBusy, isFalse);
    });
  });

  group('provider and network failure', () {
    test('an offline reply is flagged so the UI can style it', () async {
      final invoker = FakeAssistantInvoker(
        (_) async => const AssistantAnswer.offline(),
      );
      final answer = await BusinessAssistantService(invoker).answer('totals?');

      expect(answer.offline, isTrue);
      expect(answer.text, AssistantAnswer.defaultOfflineMessage);
    });

    test('a normal provider answer is not flagged offline', () async {
      final invoker = FakeAssistantInvoker(
        (_) async => const AssistantAnswer.answer('You received 400 kg.'),
      );
      final answer = await BusinessAssistantService(invoker).answer('totals?');

      expect(answer.offline, isFalse);
      expect(answer.text, 'You received 400 kg.');
    });
  });

  group('screen behaviour', () {
    testWidgets('shows a loading indicator while the answer is pending', (
      tester,
    ) async {
      final gate = Completer<AssistantAnswer>();
      final invoker = FakeAssistantInvoker((_) => gate.future);

      await tester.pumpWidget(host(BusinessAssistantService(invoker)));

      await tester.enterText(find.byType(TextField), 'How much today?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      // A spinner is visible while waiting for the server.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(invoker.calls, 1);

      gate.complete(const AssistantAnswer.answer('You received 400 kg.'));
      await tester.pumpAndSettle();

      expect(find.text('You received 400 kg.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows the offline message when there is no connection', (
      tester,
    ) async {
      final invoker = FakeAssistantInvoker(
        (_) async => const AssistantAnswer.offline(),
      );

      await tester.pumpWidget(host(BusinessAssistantService(invoker)));

      await tester.enterText(find.byType(TextField), 'totals?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(find.text(AssistantAnswer.defaultOfflineMessage), findsOneWidget);
    });

    testWidgets('the send button is disabled while a request is running', (
      tester,
    ) async {
      final gate = Completer<AssistantAnswer>();
      final invoker = FakeAssistantInvoker((_) => gate.future);

      await tester.pumpWidget(host(BusinessAssistantService(invoker)));

      await tester.enterText(find.byType(TextField), 'first?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      // While the spinner is up the send action is null, so a second tap on the
      // button cannot start another provider call.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing);

      gate.complete(const AssistantAnswer.answer('done'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('the greeting no longer promises offline answers', (
      tester,
    ) async {
      final invoker = FakeAssistantInvoker(
        (_) async => const AssistantAnswer.answer('ok'),
      );

      await tester.pumpWidget(host(BusinessAssistantService(invoker)));

      // The old local assistant told the user it worked from local SQLite.
      // That claim is gone, and the assistant now says it never changes data.
      expect(find.textContaining('local SQLite'), findsNothing);
      expect(find.textContaining('never change any data'), findsOneWidget);
    });
  });
}

