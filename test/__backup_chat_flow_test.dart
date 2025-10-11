// 梨꾪똿 ?뚮줈???꾨컲??寃利앺븯???듯빀 ?꾩젽/濡쒖쭅 ?뚯뒪??
// 踰붿쐞:
// - ?꾩넚/?ㅽ듃由щ컢/?꾨즺 UI ?꾩씠
// - 痍⑥냼 ??濡ㅻ갚 ?숈옉怨??몄뀡 珥덇린??
// - ?덉씠?꾩썐 鍮꾩쑉 諛??몄뀡 ??댄? ?몄텧
// - 紐⑤뜽 ?좏슚??寃利?????좏깮 ?쒕∼?ㅼ슫 ?몄텧
// - ?ㅻ낫???⑥텞??Shift+Enter) ?꾩넚
// - ?ㅻ쪟 諛곕꼫 諛??ъ떆???숈옉
// - API ?몄텧 ?댁뿉 placeholder 誘명룷??寃利???
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
      if (tokenDelay == Duration.zero) {
        await Future<void>.value();
      } else {
        await Future.any([Future.delayed(tokenDelay), cancel.onCancel]);
      }
      if (cancel.isCancelled) break;
      yield t;
    }
  }
} // 泥??몄텧留??ㅽ뙣?섍퀬 ?댄썑 ?뺤긽 ?숈옉?섎뒗 媛吏??대씪?댁뼵??

class _FlakyLlmClient extends _FakeLlmClient {
  bool failNext = true;
  _FlakyLlmClient({
    Duration tokenDelay = const Duration(milliseconds: 10),
    List<String>? tokensToEmit,
  }) : super(tokenDelay: tokenDelay, tokensToEmit: tokensToEmit);
  @override
  Stream<String> streamChat({
    required List<ChatTurn> turns,
    required LlmModel model,
    required CancellationToken cancel,
  }) async* {
    if (failNext) {
      failNext = false;
      yield* Stream<String>.error(Exception('network'));
      return;
    }
    yield* super.streamChat(turns: turns, model: model, cancel: cancel);
  }
} // 痍⑥냼 ?좏샇媛 ???뚭퉴吏 ?湲고븯??媛吏??대씪?댁뼵??

class _BlockingClient implements LlmClient {
  @override
  Stream<String> streamChat({
    required List<ChatTurn> turns,
    required LlmModel model,
    required CancellationToken cancel,
  }) async* {
    await cancel.onCancel;
  }
} // ?꾨떖???댁쓣 罹≪쿂留??섎뒗 媛吏??대씪?댁뼵??

class _CapturingClient implements LlmClient {
  final void Function(List<ChatTurn>) onCapture;
  _CapturingClient(this.onCapture);
  @override
  Stream<String> streamChat({
    required List<ChatTurn> turns,
    required LlmModel model,
    required CancellationToken cancel,
  }) async* {
    onCapture(turns);
    yield* const Stream<String>.empty();
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

    await tester.enterText(find.byKey(const Key('input-field')), 'Hi');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();

    final TextField input = tester.widget(find.byKey(const Key('input-field')));
    expect(input.enabled, isFalse);
    expect(find.widgetWithText(ElevatedButton, 'Cancel'), findsOneWidget);
    expect(find.textContaining('Waiting'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));

    final TextField input2 = tester.widget(
      find.byKey(const Key('input-field')),
    );
    expect(input2.enabled, isTrue);
    expect(find.widgetWithText(ElevatedButton, 'Send'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel'));
    await tester.pump();

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

    await tester.enterText(find.byKey(const Key('input-field')), 'First');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('First'), findsWidgets);
  });

  test('Model validation and persistence', () async {
    final tmpDir = await Directory.systemTemp.createTemp('humble_agent_test_');
    final storage = StorageService(baseDir: tmpDir.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);

    final openaiInvalid = LlmModel(
      id: 'o1',
      provider: 'openai',
      model: 'gpt-4o',
      apiKey: '',
    );
    expect(controller.validateModel(openaiInvalid), isFalse);
    final openaiValid = LlmModel(
      id: 'o2',
      provider: 'openai',
      model: 'gpt-4o',
      apiKey: 'x',
    );
    expect(await controller.addModel(openaiValid), isTrue);
    final ollamaInvalid = LlmModel(
      id: 'ol1',
      provider: 'ollama',
      model: 'llama3',
    );
    expect(controller.validateModel(ollamaInvalid), isFalse);
    final ollamaValid = LlmModel(
      id: 'ol2',
      provider: 'ollama',
      model: 'llama3',
      baseUrl: 'http://localhost:11434',
    );
    expect(await controller.addModel(ollamaValid, activate: false), isTrue);

    final cfg = await storage.loadConfig();
    expect((cfg['models'] as List).length, 2);
    expect(cfg['selectedModelId'], 'o2');
  });

  testWidgets('Shift+Enter sends message', (tester) async {
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

    await tester.tap(find.byKey(const Key('input-field')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('input-field')), 'Hi');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Hello world!'), findsOneWidget);
  });

  testWidgets('Model dropdown appears when models exist', (tester) async {
    final tmpDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('humble_agent_test_'),
    );
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    await tester.runAsync(
      () => controller.addModel(
        const LlmModel(
          id: 'o2',
          provider: 'openai',
          model: 'gpt-4o',
          apiKey: 'x',
        ),
      ),
    );

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
    final tmpDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('humble_agent_test_'),
    );
    final storage = StorageService(baseDir: tmpDir?.path);
    late List<ChatTurn> capturedTurns;
    final client = _CapturingClient((turns) => capturedTurns = turns);
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(
      const LlmModel(
        id: 'm1',
        provider: 'openai',
        model: 'gpt-test',
        apiKey: 'k',
      ),
    );
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
    expect(capturedTurns.map((t) => t.role).toList(), [
      'user',
      'assistant',
      'user',
    ]);
    expect(capturedTurns.last.content, 'Hi');
  });

  testWidgets('New Chat cancels in-flight request', (tester) async {
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
    expect(controller.sending, isTrue);
    await tester.tap(find.text('New Chat').first);
    await tester.pump();
    expect(controller.sending, isFalse);
    expect(controller.current!.messages, isEmpty);
  });

  testWidgets('Session list bolds selected and can delete sessions', (
    tester,
  ) async {
    // ?몄뀡 紐⑸줉?먯꽌 ?좏깮????ぉ? 蹂쇰뱶濡??쒖떆?섎ŉ, ??젣 踰꾪듉???쒓굅?섏뿀?뚯쓣 ?뺤씤?⑸땲??
    // ?먰븳 紐⑤뱺 ?몄뀡????젣?덉쓣 ???먮룞?쇰줈 ???몄뀡???앹꽦?섎뒗吏 寃利앺빀?덈떎.
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
    await controller.newSession();
    await tester.pump();

    // ?좏깮 ??ぉ? 蹂쇰뱶 ?쒖떆
    await tester.tap(find.byType(ListTile).at(2));
    await tester.pump();
    final textWidget = tester.widget<Text>(
      find.descendant(
        of: find.byType(ListTile).at(2),
        matching: find.byType(Text),
      ),
    );
    expect(textWidget.style?.fontWeight, FontWeight.bold);

    // ??젣 踰꾪듉???щ씪議뚯쓬??蹂댁옣 (?고겢由?而⑦뀓?ㅽ듃 硫붾돱濡??泥?
    expect(find.byKey(const Key('delete-session-0')), findsNothing);

    // 而⑦듃濡ㅻ윭 API濡?紐⑤뱺 ?몄뀡????젣 -> 留덉?留???젣 ???먮룞?쇰줈 ???몄뀡??1媛??앹꽦?섏뼱????
    while (true) {
      final len = controller.sessions.length;
      await tester.runAsync(() => controller.deleteSessionAt(0));
      if (len <= 1) break;
    }
    await tester.pump();
    expect(controller.sessions.length, 1);
  });
  testWidgets('Error banner with Retry resends last prompt', (tester) async {
    final tmpDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('humble_agent_test_'),
    );
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FlakyLlmClient(tokenDelay: Duration.zero)
      ..tokensToEmit = const ['OK'];
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
    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.byKey(const Key('retry-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-button')));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(find.byKey(const Key('error-banner')), findsNothing);
    expect(find.text('OK'), findsOneWidget);
  });
}

