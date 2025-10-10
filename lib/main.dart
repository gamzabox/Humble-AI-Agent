import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/chat_controller.dart';
import 'services/llm_client.dart';
import 'services/llm_client_impl.dart';
import 'services/storage_service.dart';
import 'widgets/chat_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatController(storage: StorageService(), client: RoutingLlmClient()),
      child: MaterialApp(
        title: 'Humble AI Agent',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const ChatPage(),
      ),
    );
  }
}
