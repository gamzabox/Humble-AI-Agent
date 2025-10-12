// 기본 위젯 스모크 테스트
// 목적: Provider/Storage/LLM 클라이언트가 주입된 상태에서
// ChatPage가 정상적으로 빌드되는지 빠르게 검증합니다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:humble_ai_agent/widgets/chat_page.dart';
import 'package:humble_ai_agent/controllers/chat_controller.dart';
import 'package:humble_ai_agent/services/llm_client_impl.dart';
import 'package:humble_ai_agent/services/storage_service.dart';

void main() {
  testWidgets('Smoke - ChatPage builds', (tester) async {
    // ChatController를 ChangeNotifierProvider로 주입하고,
    // 최소한의 MaterialApp 환경에서 ChatPage를 렌더링합니다.
    late ChatController controller;
    final client = RoutingLlmClient();
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('humble_agent_test_');
      final storage = StorageService(baseDir: dir.path);
      controller = ChatController(storage: storage, client: client);
      await controller.ready;
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ChatPage()),
      ),
    );

    await tester.pump(); // 첫 프레임 렌더 후 안정화

    // 기대: ChatPage 위젯이 정확히 하나 존재
    expect(find.byType(ChatPage), findsOneWidget);
  });
}
