import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:humble_ai_agent/widgets/chat_page.dart';
import 'package:humble_ai_agent/controllers/chat_controller.dart';
import 'package:humble_ai_agent/services/llm_client.dart';
import 'package:humble_ai_agent/services/storage_service.dart';

class _FakeLlmClient implements LlmClient {
  @override
  Stream<String> streamChat({required List<ChatTurn> turns, required LlmModel model, required CancellationToken cancel}) async* {}
}

void main() {
  testWidgets('Assistant code block renders with highlight', (tester) async {
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();

    final cur = controller.current!;
    cur.messages.add(const ChatMessage(role: 'assistant', content: '```dart\nvoid main() {}\n```'));
    controller.selectSession(cur);
    await tester.pump();

    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('All fenced code blocks are highlighted', (tester) async {
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();

    const multi = 'before\n\n```dart\nvoid a() {}\n```\n\ntext\n\n```python\nprint(1)\n```\nafter';
    controller.current!.messages.add(const ChatMessage(role: 'assistant', content: multi));
    controller.notifyListeners();
    await tester.pump();

    expect(find.byType(SelectableText), findsNWidgets(2));
  });

  testWidgets('Quoted fenced code blocks are not highlighted', (tester) async {
    final tmpDir = await tester.runAsync(() => Directory.systemTemp.createTemp('humble_agent_test_'));
    final storage = StorageService(baseDir: tmpDir?.path);
    final client = _FakeLlmClient();
    final controller = ChatController(storage: storage, client: client);
    controller.setActiveModel(const LlmModel(id: 'm1', provider: 'openai', model: 'gpt-test', apiKey: 'k'));

    await tester.pumpWidget(ChangeNotifierProvider.value(value: controller, child: const MaterialApp(home: ChatPage())));
    await tester.pump();

    const md = '> ```dart\n> void q() {}\n> ```\n\n```js\nfunction n() {}\n```';
    controller.current!.messages.add(const ChatMessage(role: 'assistant', content: md));
    controller.notifyListeners();
    await tester.pump();

    expect(find.byType(SelectableText), findsNWidgets(1));
  });
}

