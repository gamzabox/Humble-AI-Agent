import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import '../services/llm_client.dart';

import '../controllers/chat_controller.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Humble AI Agent'),
        actions: [
          if (controller.models.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: DropdownButton<LlmModel>(
                value: controller.activeModel,
                onChanged: (m) {
                  if (m != null) controller.setActiveModel(m);
                },
                items: controller.models
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text('${m.model} (${m.provider})'),
                        ))
                    .toList(),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => showDialog(context: context, builder: (_) => const _ModelSettingsDialog()),
          ),
        ],
      ),
      body: const _SplitLayout(),
    );
  }
}

class _SplitLayout extends StatefulWidget {
  const _SplitLayout();
  @override
  State<_SplitLayout> createState() => _SplitLayoutState();
}

class _SplitLayoutState extends State<_SplitLayout> {
  double ratio = 0.3; // left width ratio

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftW = constraints.maxWidth * ratio;
        final rightW = constraints.maxWidth - leftW - 6;
        return Row(
          children: [
            SizedBox(
              width: leftW,
              child: _SessionList(),
              key: const Key('left-pane'),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    ratio = (leftW + d.delta.dx) / constraints.maxWidth;
                    ratio = ratio.clamp(0.2, 0.8);
                  });
                },
                child: const VerticalDivider(width: 6),
              ),
            ),
            SizedBox(
              width: rightW,
              key: const Key('right-pane'),
              child: Column(
                children: [
                  Expanded(child: _ChatView()),
                  _InputBar(sending: controller.sending),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SessionList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    return ListView(
      key: const Key('session-list'),
      children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('New Chat'),
          onTap: () {
            if (controller.sending) controller.cancel();
            controller.newSession();
          },
        ),
        for (var i = 0; i < controller.sessions.length; i++)
          Builder(builder: (context) {
            final s = controller.sessions[i];
            final selected = controller.current == s;
            return ListTile(
              title: Text(
                s.title.isEmpty ? 'New Chat' : s.title,
                style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal),
              ),
              selected: selected,
              onTap: () => controller.selectSession(s),
              trailing: IconButton(
                key: Key('delete-session-$i'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => controller.deleteSessionAt(i),
              ),
            );
          }),
      ],
    );
  }
}

class _ChatView extends StatefulWidget {
  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
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
    return ListView.builder(
      controller: _scroll,
      key: const Key('chat-list'),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final m = messages[index];
        final align = m.role == 'user' ? CrossAxisAlignment.end : CrossAxisAlignment.start;
        final bg = m.role == 'status'
            ? Colors.red.shade50
            : (m.role == 'user' ? Colors.blue.shade50 : Colors.grey.shade200);
        final child = m.role == 'assistant'
            ? _AssistantContent(m.content)
            : Text(m.content, style: TextStyle(color: m.role == 'status' ? Colors.red : null));
        return Column(
          crossAxisAlignment: align,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
    );
  }
}

class _InputBar extends StatefulWidget {
  final bool sending;
  const _InputBar({required this.sending});
  @override
  State<_InputBar> createState() => _InputBarState();
}

class _ModelSettingsDialog extends StatefulWidget {
  const _ModelSettingsDialog();
  @override
  State<_ModelSettingsDialog> createState() => _ModelSettingsDialogState();
}

class _ModelSettingsDialogState extends State<_ModelSettingsDialog> {
  String provider = 'openai';
  final modelCtrl = TextEditingController();
  final apiKeyCtrl = TextEditingController();
  final baseUrlCtrl = TextEditingController(text: 'http://localhost:11434');
  String? error;

  @override
  void dispose() {
    modelCtrl.dispose();
    apiKeyCtrl.dispose();
    baseUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    return AlertDialog(
      title: const Text('Model Settings'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Model'),
            Row(
              children: [
                Radio<String>(value: 'openai', groupValue: provider, onChanged: (v) => setState(() => provider = v!)),
                const Text('OpenAI'),
                const SizedBox(width: 12),
                Radio<String>(value: 'ollama', groupValue: provider, onChanged: (v) => setState(() => provider = v!)),
                const Text('Ollama'),
              ],
            ),
            TextField(decoration: const InputDecoration(labelText: 'Model'), controller: modelCtrl),
            TextField(decoration: const InputDecoration(labelText: 'API Key'), controller: apiKeyCtrl, enabled: provider == 'openai'),
            TextField(decoration: const InputDecoration(labelText: 'Base URL'), controller: baseUrlCtrl, enabled: provider == 'ollama'),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 12),
            const Divider(),
            const Text('Existing Models'),
            ...chat.models.map((m) => ListTile(
                  title: Text('${m.model} (${m.provider})'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (chat.activeModel?.id != m.id)
                      TextButton(onPressed: () => chat.setActiveModel(m), child: const Text('Select')),
                    IconButton(onPressed: () => chat.removeModel(m.id), icon: const Icon(Icons.delete_outline)),
                  ]),
                )),
            const SizedBox(height: 12),
            const Divider(),
            const Text('About'),
            const Text('Humble AI Agent\nAuthor: gamzabox\nVersion: 1.0.0+1'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ElevatedButton(
          onPressed: () async {
            final model = LlmModel(
              id: '${provider}:${modelCtrl.text.trim()}',
              provider: provider,
              model: modelCtrl.text.trim(),
              apiKey: provider == 'openai' ? apiKeyCtrl.text.trim() : null,
              baseUrl: provider == 'ollama' ? baseUrlCtrl.text.trim() : null,
            );
            final ok = await chat.addModel(model, activate: true);
            if (!ok) {
              setState(() => error = provider == 'openai' ? 'Model and API Key required' : 'Model and Base URL required');
              return;
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _InputBarState extends State<_InputBar> {
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
          Row(
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
                    chat.send(_controller.text.trim());
                    if (!chat.sending) return;
                    // Clear local input display; content is in messages
                    _controller.clear();
                  }
                },
                child: Text(isSending ? 'Cancel' : 'Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssistantContent extends StatelessWidget {
  final String content;
  const _AssistantContent(this.content);

  @override
  Widget build(BuildContext context) {
    final fence = '```';
    final idx = content.indexOf(fence);
    if (idx == -1) return MarkdownBody(data: content);
    final end = content.indexOf(fence, idx + fence.length);
    if (end == -1) return MarkdownBody(data: content);
    final before = content.substring(0, idx);
    final infoLineEnd = content.indexOf('\n', idx + fence.length);
    final info = infoLineEnd != -1 ? content.substring(idx + fence.length, infoLineEnd).trim() : '';
    final codeStart = (infoLineEnd != -1) ? infoLineEnd + 1 : idx + fence.length;
    final code = content.substring(codeStart, end);
    final after = content.substring(end + fence.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (before.trim().isNotEmpty) MarkdownBody(data: before.trim()),
        Container(
          key: const Key('code-block'),
          padding: const EdgeInsets.all(8),
          color: Colors.grey.shade100,
          child: HighlightView(
            code,
            language: info.isEmpty ? 'plaintext' : info,
            theme: githubTheme,
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        if (after.trim().isNotEmpty) MarkdownBody(data: after.trim()),
      ],
    );
  }
}
