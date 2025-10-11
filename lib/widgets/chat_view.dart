import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/chat_controller.dart';
import 'assistant_content.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scroll = ScrollController();

  void _postScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _postScroll();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    final session = controller.current;
    final messages = session?.messages ?? const [];
    _postScroll();
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        key: const Key('chat-list'),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final m = messages[index];
          final align = m.role == 'user'
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start;
          if (m.role == 'assistant') {
            return Column(
              crossAxisAlignment: align,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: AssistantContent(m.content),
                ),
              ],
            );
          }

          final bg = m.role == 'status'
              ? Colors.red.shade50
              : Colors.blue.shade50; // user bubble color
          final child = Text(
            m.content,
            style:
                TextStyle(color: m.role == 'status' ? Colors.red : null),
          );

          return Column(
            crossAxisAlignment: align,
            children: [
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: child,
              ),
            ],
          );
        },
      ),
    );
  }
}

