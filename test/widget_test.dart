import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:humble_ai_agent/widgets/chat_page.dart';
import 'package:humble_ai_agent/controllers/chat_controller.dart';
import 'package:humble_ai_agent/services/llm_client_impl.dart';
import 'package:humble_ai_agent/services/storage_service.dart';

void main() {
  testWidgets('Smoke - ChatPage builds', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ChatController(storage: StorageService(), client: RoutingLlmClient()),
      child: const MaterialApp(home: ChatPage()),
    ));
    await tester.pump();
    expect(find.byType(ChatPage), findsOneWidget);
  });
}
