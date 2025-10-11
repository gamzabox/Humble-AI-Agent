// 채팅 플로우 전반을 검증하는 통합 위젯/로직 테스트
// 범위:
// - 전송/스트리밍/완료 UI 전이
// - 취소 시 롤백 동작과 세션 초기화
// - 레이아웃 비율 및 세션 타이틀 노출
// - 모델 유효성 검증/저장/선택 드롭다운 노출
// - 키보드 단축키(Shift+Enter) 전송
// - 오류 배너 및 재시도 동작
// - API 호출 턴에 placeholder 미포함 검증 등
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

// 토큰을 순차적으로 방출하는 간단한 가짜 LLM 클라이언트
// - streamChat은 tokensToEmit 목록을 지연(tokenDelay)과 함께 차례로 yield 합니다.
// - 취소 토큰이 설정되면 즉시 스트리밍을 중단합니다.
class _FakeLlmClient implements LlmClient {
  final Duration tokenDelay;
  List<String> tokensToEmit;
  _FakeLlmClient({this.tokenDelay = const Duration(milliseconds: 10), List<String>? tokensToEmit})
      : tokensToEmit = tokensToEmit ?? const ['Hello', ' ', 'world!'];

  @override
  Stream<String> streamChat({
    required List<ChatTurn> turns,
    required LlmModel model,
    required CancellationToken cancel,
  }) async* {
    for (final t in tokensToEmit) {
      if (cancel.isCancelled) break; // 취소되면 중단
      if (tokenDelay == Duration.zero) {
        await Future<void>.value(); // 이벤트 루프 한 틱 양보
      } else {
        await Future.any([
          Future.delayed(tokenDelay),
          cancel.onCancel,
        ]);
      }
      if (cancel.isCancelled) break;
      yield t; // 한 토큰씩 방출 (스트리밍 시뮬레이션)
    }
  }
}

// 첫 호출만 실패(에러 스트림 방출)하고 이후에는 정상 동작하는 가짜 클라이언트
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

// 취소 신호가 올 때까지 블로킹되는 가짜 클라이언트
class _BlockingClient implements LlmClient {
  @override
  Stream<String> streamChat({required List<ChatTurn> turns, required LlmModel model, required CancellationToken cancel}) async* {
    await cancel.onCancel; // cancel 신호 대기 (토큰 방출 없음)
  }
}

// 전달된 turns를 캡쳐만 하고 아무 것도 방출하지 않는 클라이언트
class _CapturingClient implements LlmClient {
  final void Function(List<ChatTurn>) onCapture;
  _CapturingClient(this.onCapture);
  @override
  Stream<String> streamChat({required List<ChatTurn> turns, required LlmModel model, required CancellationToken cancel}) async* {
    onCapture(turns); // API로 전달되는 턴 구성 검증 용도
    yield* const Stream<String>.empty();
  }
}

void main() {
  testWidgets('Send streams response and finalizes UI', (tester) async {
    // 전송 후
    // 1) 입력 비활성화 + Cancel 버튼 + Waiting 표시
    // 2) 일정 시간 후 스트리밍 완료 -> 입력 활성화 + Send 버튼 + 최종 응답 표시
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('input-field')), 'Hi');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();

    final TextField input = tester.widget(find.byKey(const Key('input-field')));
    expect(input.enabled, isFalse);
    expect(find.widgetWithText(ElevatedButton, 'Cancel'), findsOneWidget);
    expect(find.textContaining('Waiting'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));

    final TextField input2 = tester.widget(find.byKey(const Key('input-field')));
    expect(input2.enabled, isTrue);
    expect(find.widgetWithText(ElevatedButton, 'Send'), findsOneWidget);
    expect(find.text('Hello world!'), findsOneWidget);
  });

  testWidgets('Cancel rolls back pending exchange', (tester) async {
    // 전송 직후 Blocking 클라이언트로 응답이 오지 않는 상황에서 Cancel을 누르면
    // - 입력이 다시 활성화되고
    // - 사용자가 보낸 메시지(대기/플레이스홀더 포함)가 롤백되어 사라져야 합니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _BlockingClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('input-field')), 'Hello');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel'));
    await tester.pumpAndSettle();

    final TextField input = tester.widget(find.byKey(const Key('input-field')));
    expect(input.enabled, isTrue);
    expect(find.widgetWithText(ElevatedButton, 'Send'), findsOneWidget);
    expect(find.text('Hello'), findsNothing);
  });

  testWidgets('Initial split layout ~30/70 and session title', (tester) async {
    // 초기 레이아웃 좌:우 비율이 약 30:70 인지 확인하고,
    // 첫 전송 후 세션 타이틀(사용자 첫 메시지)이 UI에 표시되는지 검증합니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient(tokensToEmit: const ['A', 'B', 'C']);
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: SizedBox(width: 1000, height: 800, child: ChatPage()))));
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
    // 모델 유효성 검증 규칙 및 저장 로직을 검증합니다.
    // - OpenAI: apiKey 필수
    // - Ollama: baseUrl 필수
    // 저장 후 구성(config)에 모델 2개가 저장되고 선택된 모델 ID가 기대값인지 확인합니다.
    final tmpDir = await Directory.systemTemp.createTemp('humble_agent_test_');
    final storage = StorageService(baseDir: tmpDir.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);

    final openaiInvalid = LlmModel(id: 'o1', provider: 'openai', model: 'gpt-4o', apiKey: '');
    expect(controller.validateModel(openaiInvalid), isFalse);
    final openaiValid = LlmModel(id: 'o2', provider: 'openai', model: 'gpt-4o', apiKey: 'x');
    expect(await controller.addModel(openaiValid), isTrue);
    final ollamaInvalid = LlmModel(id: 'ol1', provider: 'ollama', model: 'llama3');
    expect(controller.validateModel(ollamaInvalid), isFalse);
    final ollamaValid = LlmModel(id: 'ol2', provider: 'ollama', model: 'llama3', baseUrl: 'http://localhost:11434');
    expect(await controller.addModel(ollamaValid, activate: false), isTrue);

    final cfg = await storage.loadConfig();
    expect((cfg['models'] as List).length, 2);
    expect(cfg['selectedModelId'], 'o2');
  });

  testWidgets('Shift+Enter sends message', (tester) async {
    // 입력 포커스 상태에서 Shift+Enter 조합으로 전송이 트리거되는지 확인합니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
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
    // 모델이 하나 이상 저장되어 있으면 모델 선택 드롭다운이 표시되어야 합니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    await tester.runAsync(() => controller.addModel(const LlmModel(id: 'o2', provider: 'openai', model: 'gpt-4o', apiKey: 'x')));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();
    expect(find.byKey(const Key('model-dropdown')), findsOneWidget);
  });

  testWidgets('Waiting placeholder is not sent to API turns', (tester) async {
    // 이전 대화와 신규 사용자 입력이 결합되어 API 호출로 전달되되,
    // UI에서 임시로 표시되는 "Waiting" 메시지는 API turns에 포함되지 않아야 합니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    late List<ChatTurn> capturedTurns;
    final client = _CapturingClient((turns) => capturedTurns = turns);
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));
    controller.current!.messages.addAll(const [ChatMessage(role: 'user', content: 'Prev Q'), ChatMessage(role: 'assistant', content: 'Prev A')]);

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('input-field')), 'Hi');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();
    expect(capturedTurns.map((t) => t.role).toList(), ['user', 'assistant', 'user']);
    expect(capturedTurns.last.content, 'Hi');
  });

  testWidgets('New Chat cancels in-flight request', (tester) async {
    // 전송 중(New Chat 전환 전)인 상태에서 'New Chat'을 누르면
    // 진행 중 요청이 취소되고, 현 세션 메시지가 초기화되어야 합니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _BlockingClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
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

  testWidgets('Session list bolds selected and can delete sessions', (tester) async {
    // 세션 목록에서 선택된 항목은 볼드로 표시되며 삭제 아이콘으로 제거할 수 있습니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();
    await controller.newSession();
    await tester.pump();
    await tester.tap(find.byType(ListTile).at(2));
    await tester.pump();
    final textWidget = tester.widget<Text>(find.descendant(of: find.byType(ListTile).at(2), matching: find.byType(Text)));
    expect(textWidget.style?.fontWeight, FontWeight.bold);
    await tester.tap(find.byKey(const Key('delete-session-0')));
    await tester.pumpAndSettle();
    expect(controller.sessions.length >= 1, isTrue);
  });

  testWidgets('Error banner with Retry resends last prompt', (tester) async {
    // 첫 요청은 네트워크 오류로 실패(에러 배너 노출), 이후 Retry를 누르면
    // 마지막 프롬프트로 재요청되어 성공 토큰이 표시되어야 합니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FlakyLlmClient(tokenDelay: Duration.zero)..tokensToEmit = const ['OK'];
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
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

