import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/chat_controller.dart';

class InputBar extends StatefulWidget {
  final bool sending;
  const InputBar({super.key, required this.sending});
  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final isSending = widget.sending;
    void sendNow() {
      if (isSending) return;
      chat.send(_controller.text.trim());
      if (!chat.sending) return;
      _controller.clear();
    }
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chat.lastError != null)
            Container(
              key: const Key('error-banner'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(chat.lastError!)),
                  TextButton(
                    key: const Key('retry-button'),
                    onPressed: chat.retryLast,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter, shift: true):
                  SendMessageIntent(),
            },
            child: Actions(
              actions: {
                SendMessageIntent: CallbackAction<SendMessageIntent>(
                  onInvoke: (intent) {
                    sendNow();
                    return null;
                  },
                ),
              },
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('input-field'),
                      controller: _controller,
                      enabled: !isSending,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const Key('send-button'),
                    onPressed: () {
                      if (isSending) {
                        chat.cancel();
                      } else {
                        sendNow();
                      }
                    },
                    child: Text(isSending ? 'Cancel' : 'Send'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SendMessageIntent extends Intent {
  const SendMessageIntent();
}

