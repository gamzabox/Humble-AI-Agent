// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:humble_ai_agent/widgets/chat_page.dart';
import 'package:humble_ai_agent/controllers/chat_controller.dart';
import 'package:humble_ai_agent/services/llm_client.dart';
import 'package:humble_ai_agent/services/storage_service.dart';

  class _FakeLlmClient implements LlmClient {
  final Duration tokenDelay;
  List<String> tokensToEmit;
  _FakeLlmClient({
    this.tokenDelay = const Duration(milliseconds: 10),
    List<String>? tokensToEmit,
  }) : tokensToEmit = tokensToEmit ?? const ['Hello', ' ', 'world!'];

  @override
  Stream<String> streamChat({
    required List<ChatTurn> turns,
    required LlmModel model,
    required CancellationToken cancel,
  }) async* {
    for (final t in tokensToEmit) {
      if (cancel.isCancelled) break;
      // Allow cancellation to break the delay to avoid pending timers.
      if (tokenDelay == Duration.zero) {
        // Immediate proceed without scheduling timers.
        await Future<void>.value();
      } else {
        await Future.any([
          Future.delayed(tokenDelay),
          cancel.onCancel,
        ]);
      }
      if (cancel.isCancelled) break;
      yield t;
    }
  }

}

  class _FlakyLlmClient extends _FakeLlmClient {
    bool failNext = true;
    _FlakyLlmClient({super.tokenDelay, super.tokensToEmit});
    @override
    Stream<String> streamChat({required List<ChatTurn> turns, required LlmModel model, required CancellationToken cancel}) async* {
      if (failNext) {
        failNext = false;
        yield* Stream<String>.error(Exception('network'));
        return;
      }
      yield* super.streamChat(turns: turns, model: model, cancel: cancel);
    }
  }

void main() {
  testWidgets('Send streams response and finalizes UI', (tester) async {
    final tmpDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('humble_agent_test_'),
    );
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(
      const LlmModel(
        id: 'm1',
        provider: 'openai',
        model: 'gpt-test',
        apiKey: 'k',
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ChatPage()),
      ),
    );

    await tester.pump();

    // Enter a prompt and send.
    await tester.enterText(find.byKey(const Key('input-field')), 'Hi');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();

    // Input disabled and button shows Cancel
    final TextField input = tester.widget(find.byKey(const Key('input-field')));
    expect(input.enabled, isFalse);
    expect(find.widgetWithText(ElevatedButton, 'Cancel'), findsOneWidget);

    // Waiting placeholder appears
    expect(find.textContaining('Waiting'), findsOneWidget);

    // Stream tokens and finalize
    // Let streaming progress
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Input re-enabled, button restored
    final TextField input2 = tester.widget(
      find.byKey(const Key('input-field')),
    );
    expect(input2.enabled, isTrue);
    expect(find.widgetWithText(ElevatedButton, 'Send'), findsOneWidget);

    // Assistant message combined
    expect(find.text('Hello world!'), findsOneWidget);
  });

  testWidgets('Cancel rolls back pending exchange', (tester) async {
    final tmpDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('humble_agent_test_'),
    );
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _BlockingClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(
      const LlmModel(
        id: 'm1',
        provider: 'openai',
        model: 'gpt-test',
        apiKey: 'k',
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ChatPage()),
      ),
    );

    await tester.pump();

    await tester.enterText(find.byKey(const Key('input-field')), 'Hello');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();

    // Cancel quickly before any token
    await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Input restored, no messages retained
    final TextField input = tester.widget(find.byKey(const Key('input-field')));
    expect(input.enabled, isTrue);
    expect(find.widgetWithText(ElevatedButton, 'Send'), findsOneWidget);
    expect(find.text('Hello'), findsNothing);
  });

  testWidgets('Initial split layout ~30/70 and session title', (tester) async {
    final tmpDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('humble_agent_test_'),
    );
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient(tokensToEmit: const ['A', 'B', 'C']);
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(
      const LlmModel(
        id: 'm1',
        provider: 'openai',
        model: 'gpt-test',
        apiKey: 'k',
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: SizedBox(width: 1000, height: 800, child: ChatPage()),
        ),
      ),
    );

    await tester.pump();

    final left = tester.getSize(find.byKey(const Key('left-pane'))).width;
    final right = tester.getSize(find.byKey(const Key('right-pane'))).width;
    final ratio = left / (left + right + 6);
    expect(ratio, inInclusiveRange(0.29, 0.31));

    // Title updates on first user message
    await tester.enterText(find.byKey(const Key('input-field')), 'First');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));

    expect(
      find.text('First'),
      findsWidgets,
    ); // appears in session list title or bubbles
  });

  test('Model validation and persistence', () async {
    final tmpDir = await Directory.systemTemp.createTemp('humble_agent_test_');
    final storage = StorageService(baseDir: tmpDir.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);

    // Invalid OpenAI (missing key)
    final openaiInvalid = LlmModel(
      id: 'o1',
      provider: 'openai',
      model: 'gpt-4o',
      apiKey: '',
    );
    expect(controller.validateModel(openaiInvalid), isFalse);

    // Valid OpenAI
    final openaiValid = LlmModel(
      id: 'o2',
      provider: 'openai',
      model: 'gpt-4o',
      apiKey: 'x',
    );
    expect(await controller.addModel(openaiValid), isTrue);

    // Invalid Ollama (missing base URL)
    final ollamaInvalid = LlmModel(
      id: 'ol1',
      provider: 'ollama',
      model: 'llama3',
    );
    expect(controller.validateModel(ollamaInvalid), isFalse);

    // Valid Ollama
    final ollamaValid = LlmModel(
      id: 'ol2',
      provider: 'ollama',
      model: 'llama3',
      baseUrl: 'http://localhost:11434',
    );
    expect(await controller.addModel(ollamaValid, activate: false), isTrue);

    // Persisted
    final cfg = await storage.loadConfig();
    expect((cfg['models'] as List).length, 2);
    expect(cfg['selectedModelId'], 'o2');
  });

  testWidgets('Shift+Enter sends message', (tester) async {
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(
      const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    // Focus input and type
    await tester.tap(find.byKey(const Key('input-field')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('input-field')), 'Hi');

    // Simulate Shift+Enter
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 100));

    // Assistant response should appear
    expect(find.text('Hello world!'), findsOneWidget);
  });

  testWidgets('Model dropdown appears when models exist', (tester) async {
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    await tester.runAsync(() => controller.addModel(
          const LlmModel(id: 'o2', provider: 'openai', model: 'gpt-4o', apiKey: 'x'),
        ));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('model-dropdown')), findsOneWidget);
  });

  testWidgets('Waiting placeholder is not sent to API turns', (tester) async {
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    late List<ChatTurn> capturedTurns;

    final client = _CapturingClient((turns) => capturedTurns = turns);
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    // Seed with previous exchange
    controller.current!.messages.addAll(const [
      ChatMessage(role: 'user', content: 'Prev Q'),
      ChatMessage(role: 'assistant', content: 'Prev A'),
    ]);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('input-field')), 'Hi');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();

    // Turns should include only previous exchange + new user, without waiting placeholder
    expect(capturedTurns.map((t) => t.role).toList(), ['user', 'assistant', 'user']);
    expect(capturedTurns.last.content, 'Hi');
  });

  testWidgets('New Chat cancels in-flight request', (tester) async {
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _BlockingClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('input-field')), 'Hello');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();
    expect(controller.sending, isTrue);

    // Tap New Chat on left pane
    await tester.tap(find.text('New Chat').first);
    await tester.pump();

    expect(controller.sending, isFalse);
    expect(controller.current!.messages, isEmpty);
  });

  testWidgets('Assistant code block renders with highlight', (tester) async {
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(
      const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ChatPage()),
      ),
    );

    // Inject assistant message containing code block
    final cur = controller.current!;
    cur.messages.add(const ChatMessage(role: 'assistant', content: '```dart\nvoid main() {}\n```'));
    controller.selectSession(cur);
    await tester.pump();

    final block = find.byKey(const Key('code-block'));
    expect(block, findsOneWidget);
    final container = tester.widget<Container>(block);
    final BoxDecoration? deco = container.decoration as BoxDecoration?;
    // Light gray background like GitHub style
    expect(container.color, equals(Colors.grey.shade100));
  });


  testWidgets('Session list bolds selected and can delete sessions', (tester) async {
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(
      const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    // Create second session and select it
    await controller.newSession();
    await tester.pump();
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    // First tile is 'New Chat' button, skip it; next are sessions
    final sessionTiles = tiles.where((t) => t.leading == null).toList();
    expect(sessionTiles.length >= 2, isTrue);

    // Select the second session tile in the list view via tap
    await tester.tap(find.byType(ListTile).at(2));
    await tester.pump();

    // Bold text on selected
    final textWidget = tester.widget<Text>(find.descendant(
      of: find.byType(ListTile).at(2),
      matching: find.byType(Text),
    ));
    expect(textWidget.style?.fontWeight, FontWeight.bold);

    // Delete first session (tile at index 1 in list, skipping add tile)
    final deleteBtn = find.byKey(const Key('delete-session-0'));
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // One less session now (assert via controller state)
    expect(controller.sessions.length, sessionTiles.length - 1);
  });

  testWidgets('Error banner with Retry resends last prompt', (tester) async {
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    // Fake client that fails first, succeeds next
    final client = _FlakyLlmClient(tokenDelay: Duration.zero);
    client.tokensToEmit = const ['OK'];
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(
      const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('input-field')), 'Hello');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    // Error banner visible with Retry
    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.byKey(const Key('retry-button')), findsOneWidget);

    // Tap Retry, should stream and finalize
    await tester.tap(find.byKey(const Key('retry-button')));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();

    // Error banner gone and message present
    expect(find.byKey(const Key('error-banner')), findsNothing);
    expect(find.text('OK'), findsOneWidget);
  });
}

class _CapturingClient implements LlmClient {
  final void Function(List<ChatTurn>) onCapture;
  _CapturingClient(this.onCapture);
  @override
  Stream<String> streamChat({required List<ChatTurn> turns, required LlmModel model, required CancellationToken cancel}) async* {
    onCapture(turns);
    yield* const Stream<String>.empty();
  }
}

class _BlockingClient implements LlmClient {
  @override
  Stream<String> streamChat({required List<ChatTurn> turns, required LlmModel model, required CancellationToken cancel}) async* {
    // Wait until cancellation without creating timers
    await cancel.onCancel;
    // Then complete without emitting
  }
}


