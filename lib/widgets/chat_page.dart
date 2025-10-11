import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:markdown/markdown.dart' as md;
import '../services/llm_client.dart';

import '../controllers/chat_controller.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    return Scaffold(appBar: null, body: const _SplitLayout());
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
                  const _TopControls(),
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

class _TopControls extends StatelessWidget {
  const _TopControls();
  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (chat.models.isNotEmpty)
            DropdownButton<LlmModel>(
              key: const Key('model-dropdown'),
              value: chat.activeModel,
              onChanged: (m) {
                if (m != null) chat.setActiveModel(m);
              },
              items: chat.models
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text('${m.model} (${m.provider})'),
                    ),
                  )
                  .toList(),
            ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const _SettingsDialog(),
            ),
          ),
        ],
      ),
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
          Builder(
            builder: (context) {
              final s = controller.sessions[i];
              final selected = controller.current == s;
              return ListTile(
                title: Text(
                  s.title.isEmpty ? 'New Chat' : s.title,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: selected,
                onTap: () => controller.selectSession(s),
                trailing: IconButton(
                  key: Key('delete-session-$i'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => controller.deleteSessionAt(i),
                ),
              );
            },
          ),
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
            // Assistant answers: no bubble, render content directly with light spacing.
            return Column(
              crossAxisAlignment: align,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: _AssistantContent(m.content),
                ),
              ],
            );
          }

          final bg = m.role == 'status'
              ? Colors.red.shade50
              : Colors.blue.shade50; // user bubble color
          final child = Text(
            m.content,
            style: TextStyle(color: m.role == 'status' ? Colors.red : null),
          );

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
      ),
    );
  }
}

class _InputBar extends StatefulWidget {
  final bool sending;
  const _InputBar({required this.sending});
  @override
  State<_InputBar> createState() => _InputBarState();
}

class _ModelSettingsView extends StatefulWidget {
  const _ModelSettingsView();
  @override
  State<_ModelSettingsView> createState() => _ModelSettingsViewState();
}

class _ModelSettingsViewState extends State<_ModelSettingsView> {
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Model',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Radio<String>(
                value: 'openai',
                groupValue: provider,
                onChanged: (v) => setState(() => provider = v!),
              ),
              const Text('OpenAI'),
              const SizedBox(width: 12),
              Radio<String>(
                value: 'ollama',
                groupValue: provider,
                onChanged: (v) => setState(() => provider = v!),
              ),
              const Text('Ollama'),
            ],
          ),
          TextField(
            decoration: const InputDecoration(labelText: 'Model'),
            controller: modelCtrl,
          ),
          TextField(
            decoration: const InputDecoration(labelText: 'API Key'),
            controller: apiKeyCtrl,
            enabled: provider == 'openai',
          ),
          TextField(
            decoration: const InputDecoration(labelText: 'Base URL'),
            controller: baseUrlCtrl,
            enabled: provider == 'ollama',
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () async {
                final model = LlmModel(
                  id: '${provider}:${modelCtrl.text.trim()}',
                  provider: provider,
                  model: modelCtrl.text.trim(),
                  apiKey: provider == 'openai' ? apiKeyCtrl.text.trim() : null,
                  baseUrl: provider == 'ollama'
                      ? baseUrlCtrl.text.trim()
                      : null,
                );
                final ok = await chat.addModel(model, activate: true);
                if (!ok) {
                  setState(
                    () => error = provider == 'openai'
                        ? 'Model and API Key required'
                        : 'Model and Base URL required',
                  );
                  return;
                }
              },
              child: const Text('Add'),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const Text(
            'Existing Models',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          ...chat.models.map(
            (m) => ListTile(
              title: Text('${m.model} (${m.provider})'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chat.activeModel?.id != m.id)
                    TextButton(
                      onPressed: () => chat.setActiveModel(m),
                      child: const Text('Select'),
                    ),
                  IconButton(
                    onPressed: () => chat.removeModel(m.id),
                    icon: const Icon(Icons.delete_outline),
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

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  int selected = 0; // 0: Models, 1: About

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 720,
        height: 480,
        child: Row(
          children: [
            SizedBox(
              width: 200,
              child: ListView(
                children: [
                  ListTile(
                    selected: selected == 0,
                    title: const Text('Models'),
                    onTap: () => setState(() => selected = 0),
                  ),
                  ListTile(
                    selected: selected == 1,
                    title: const Text('About'),
                    onTap: () => setState(() => selected = 1),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: selected == 0
                    ? const _ModelSettingsView()
                    : const _AboutView(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _AboutView extends StatelessWidget {
  const _AboutView();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Humble AI Agent',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        Text('Version: 1.0.0+1'),
        Text('Developer: gamzabox'),
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
            shortcuts: <ShortcutActivator, Intent>{
              const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                  const SendMessageIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
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

class _AssistantContent extends StatelessWidget {
  final String content;
  const _AssistantContent(this.content);

  MarkdownStyleSheet _mdStyle(BuildContext context) {
    // Base Cupertino style to align with macOS-like appearance
    final cuTheme = cupertino.CupertinoTheme.of(context);
    return MarkdownStyleSheet.fromCupertinoTheme(cuTheme);
  }

  @override
  Widget build(BuildContext context) {
    final style = _mdStyle(context);
    final fence = '```';
    final builders = {'code': _InlineCodeBuilder()};
    List<Widget> children = [];
    int cursor = 0;
    while (true) {
      final start = content.indexOf(fence, cursor);
      if (start == -1) {
        final tail = content.substring(cursor);
        if (tail.trim().isNotEmpty) {
          children.add(
            MarkdownBody(
              data: tail.trim(),
              styleSheet: style,
              builders: builders,
            ),
          );
        }
        break;
      }

      // Add markdown before this fence
      if (start > cursor) {
        final before = content.substring(cursor, start);
        if (before.trim().isNotEmpty) {
          children.add(
            MarkdownBody(
              data: before.trim(),
              styleSheet: style,
              builders: builders,
            ),
          );
        }
      }

      // Determine if this fence is within a blockquote line (starts with optional spaces then '>')
      final int lineStart = start > 0
          ? content.lastIndexOf('\n', start - 1) + 1
          : 0;
      final linePrefix = content.substring(lineStart, start);
      final isBlockquoteFence = linePrefix.trimLeft().startsWith('>');

      // Find info line end
      final infoLineEnd = content.indexOf('\n', start + fence.length);
      if (infoLineEnd == -1) {
        // No newline; treat rest as markdown
        final tail = content.substring(start);
        if (tail.trim().isNotEmpty) {
          children.add(
            MarkdownBody(
              data: tail.trim(),
              styleSheet: style,
              builders: builders,
            ),
          );
        }
        break;
      }

      if (isBlockquoteFence) {
        // Skip custom highlighting: include entire blockquote-fenced code as markdown
        int searchPos = infoLineEnd + 1;
        int endFence = -1;
        while (true) {
          final nextFence = content.indexOf(fence, searchPos);
          if (nextFence == -1) break;
          final ls = content.lastIndexOf('\n', nextFence - 1) + 1;
          final prefix = content.substring(ls, nextFence);
          if (prefix.trimLeft().startsWith('>')) {
            endFence = nextFence;
            break;
          }
          searchPos = nextFence + fence.length;
        }
        if (endFence == -1) {
          final tail = content.substring(lineStart);
          children.add(
            MarkdownBody(
              data: tail.trim(),
              styleSheet: style,
              builders: builders,
            ),
          );
          break;
        } else {
          final block = content.substring(lineStart, endFence + fence.length);
          children.add(
            MarkdownBody(
              data: block.trim(),
              styleSheet: style,
              builders: builders,
            ),
          );
          cursor = endFence + fence.length;
          continue;
        }
      }

      // Non-quoted fence: highlight
      final info = content.substring(start + fence.length, infoLineEnd).trim();
      final end = content.indexOf(fence, infoLineEnd + 1);
      if (end == -1) {
        final code = content.substring(infoLineEnd + 1);
        children.add(
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade200,
            child: _SelectableHighlight(
              code: code,
              language: info.isEmpty ? 'plaintext' : info,
            ),
          ),
        );
        break;
      } else {
        final code = content.substring(infoLineEnd + 1, end);
        children.add(
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade200,
            child: _SelectableHighlight(
              code: code,
              language: info.isEmpty ? 'plaintext' : info,
            ),
          ),
        );
        cursor = end + fence.length;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _SelectableHighlight extends StatelessWidget {
  final String code;
  final String language;
  const _SelectableHighlight({required this.code, required this.language});

  TextSpan _buildSpan(List<hl.Node> nodes) {
    List<TextSpan> spans = [];
    TextStyle? styleFor(String? className) {
      if (className == null) return null;
      final parts = className.split(' ');
      TextStyle? merged;
      for (final p in parts) {
        final s = githubTheme[p];
        if (s != null) merged = (merged ?? const TextStyle()).merge(s);
      }
      return merged;
    }

    void walk(hl.Node node, List<TextSpan> out) {
      if (node.value != null) {
        out.add(TextSpan(text: node.value, style: styleFor(node.className)));
      } else if (node.children != null) {
        final children = <TextSpan>[];
        for (final c in node.children!) {
          walk(c, children);
        }
        out.add(TextSpan(children: children, style: styleFor(node.className)));
      }
    }

    for (final n in nodes) {
      walk(n, spans);
    }
    return TextSpan(
      children: spans,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
    );
  }

  @override
  Widget build(BuildContext context) {
    final res = hl.highlight.parse(code, language: language);
    final nodes = res.nodes ?? const <hl.Node>[];
    final span = _buildSpan(nodes);
    return SelectableText.rich(span);
  }
}

class _InlineCodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag == 'code') {
      final text = element.textContent;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      );
    }
    return null;
  }
}
