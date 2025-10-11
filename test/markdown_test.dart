// Markdown 렌더링 및 코드 블록 하이라이트 동작 테스트
// - 어시스턴트가 보낸 fenced code block 이 하이라이트(예: SelectableText)로 표시되는지
// - 여러 fenced code block 모두가 처리되는지
// - 인용(>)된 fenced code block 은 하이라이트 대상에서 제외되는지 검증합니다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:humble_ai_agent/widgets/chat_page.dart';
import 'package:humble_ai_agent/controllers/chat_controller.dart';
import 'package:humble_ai_agent/services/llm_client.dart';
import 'package:humble_ai_agent/services/storage_service.dart';

// 실제 LLM 호출은 필요하지 않으므로, 비어있는 스트림을 반환하는 더미 클라이언트입니다.
class _FakeLlmClient implements LlmClient {
  @override
  Stream<String> streamChat({required List<ChatTurn> turns, required LlmModel model, required CancellationToken cancel}) async* {}
}

void main() {
  testWidgets('Assistant code block renders with highlight', (tester) async {
    // 임시 디렉터리를 사용하여 테스트 간 상태 오염을 방지합니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    // 하이라이트를 테스트하기 위해 활성 모델이 설정되어 있어야 합니다.
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    // ChatPage를 필요한 Provider와 함께 마운트합니다.
    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();

    // 어시스턴트 메시지에 fenced code block을 추가하고, 선택된 세션을 갱신하여 UI 반영을 유도합니다.
    final cur = controller.current!;
    cur.messages.add(const ChatMessage(role: 'assistant', content: '```dart\nvoid main() {}\n```'));
    controller.selectSession(cur);
    await tester.pump();

    // 기대: 코드 하이라이트 위젯(여기서는 SelectableText)이 하나 표시됩니다.
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('All fenced code blocks are highlighted', (tester) async {
    // 여러 fenced code block이 있는 경우 모두 하이라이트 되는지 검증합니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();

    // 서로 다른 언어의 fenced code block 2개를 포함한 메시지를 추가합니다.
    const multi = 'before\n\n```dart\nvoid a() {}\n```\n\ntext\n\n```python\nprint(1)\n```\nafter';
    controller.current!.messages.add(const ChatMessage(role: 'assistant', content: multi));
    controller.notifyListeners();
    await tester.pump();

    // 기대: 하이라이트 위젯이 2개 표시됩니다.
    expect(find.byType(SelectableText), findsNWidgets(2));
  });

  testWidgets('Quoted fenced code blocks are not highlighted', (tester) async {
    // '>' 로 인용된 fenced code block 은 실제 코드가 아닌 인용으로 간주하므로 하이라이트 대상에서 제외되어야 합니다.
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();

    // 인용된 fenced code block 1개와, 실제 fenced code block 1개를 포함합니다.
    const md = '> ```dart\n> void q() {}\n> ```\n\n```js\nfunction n() {}\n```';
    controller.current!.messages.add(const ChatMessage(role: 'assistant', content: md));
    controller.notifyListeners();
    await tester.pump();

    // 기대: 인용된 코드는 제외되어, 하이라이트 위젯은 1개만 표시됩니다.
    expect(find.byType(SelectableText), findsNWidgets(1));
  });
}

