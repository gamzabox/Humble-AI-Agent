import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/chat_controller.dart';
import '../services/llm_client.dart';
import 'chat_view.dart';
import 'input_bar.dart';
import 'settings_dialog.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(appBar: null, body: _SplitLayout());
  }
}

class _SplitLayout extends StatefulWidget {
  const _SplitLayout();
  @override
  State<_SplitLayout> createState() => _SplitLayoutState();
}

class _SplitLayoutState extends State<_SplitLayout> {
  double ratio = 0.3;
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    return LayoutBuilder(builder: (context, constraints) {
      final leftW = constraints.maxWidth * ratio;
      final rightW = constraints.maxWidth - leftW - 6;
      return Row(children: [
        SizedBox(width: leftW, key: const Key('left-pane'), child: const _SessionList()),
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
          child: Column(children: [
            const _TopControls(),
            const Expanded(child: ChatView()),
            InputBar(sending: controller.sending),
          ]),
        )
      ]);
    });
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
      child: Row(children: [
        if (chat.models.isNotEmpty)
          DropdownButton<LlmModel>(
            key: const Key('model-dropdown'),
            value: chat.activeModel,
            onChanged: (m) {
              if (m != null) chat.setActiveModel(m);
            },
            items: chat.models
                .map((m) => DropdownMenuItem(value: m, child: Text('${m.model} (${m.provider})')))
                .toList(),
          ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () => showDialog(context: context, builder: (_) => const SettingsDialog()),
        )
      ]),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList();
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    return ListView(key: const Key('session-list'), children: [
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
    ]);
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView();
  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _scroll = ScrollController();
  void _postScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
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
          final align = m.role == 'user' ? CrossAxisAlignment.end : CrossAxisAlignment.start;
          if (m.role == 'assistant') {
            return Column(
              crossAxisAlignment: align,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: const SizedBox.shrink(),
                ),
              ],
            );
          }
          final bg = m.role == 'status' ? Colors.red.shade50 : Colors.blue.shade50;
          final child = Text(m.content, style: TextStyle(color: m.role == 'status' ? Colors.red : null));
          return Column(
            crossAxisAlignment: align,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                child: child,
              ),
            ],
          );
        },
      ),
    );
  }
}
