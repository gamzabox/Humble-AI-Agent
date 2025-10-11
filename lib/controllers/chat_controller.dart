import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/llm_client.dart';
import '../services/storage_service.dart';

class ChatMessage {
  final String role; // 'user' or 'assistant' or 'status'
  final String content;
  const ChatMessage({required this.role, required this.content});
}

class ChatSession {
  final String id;
  String title;
  final List<ChatMessage> messages;
  ChatSession({required this.id, required this.title, List<ChatMessage>? messages})
      : messages = messages ?? [];
}

class ChatController extends ChangeNotifier {
  final StorageService storage;
  final LlmClient client;

  final List<ChatSession> sessions = [];
  ChatSession? _current;
  ChatSession? get current => _current;

  bool _sending = false;
  bool get sending => _sending;

  // Models and configuration
  final List<LlmModel> _models = [];
  List<LlmModel> get models => List.unmodifiable(_models);
  LlmModel? _activeModel;
  LlmModel? get activeModel => _activeModel;

  StreamSubscription<String>? _sub;
  CancellationToken? _cancelToken;
  String? _lastError;
  String? get lastError => _lastError;
  String? _lastFailedPrompt;

  static const String waitingPlaceholder = 'Waiting Response…';

  ChatController({required this.storage, required this.client}) {
    // Ensure an initial session is available immediately for UI/tests
    _current = ChatSession(id: _genId(), title: 'New Chat');
    sessions.add(_current!);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Load sessions
    final sess = await storage.loadSessions();
    final items = (sess['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isNotEmpty) {
      sessions.clear();
      for (final s in items) {
        sessions.add(ChatSession(
          id: s['id'] as String,
          title: s['title'] as String? ?? 'New Chat',
          messages: ((s['messages'] as List?) ?? [])
              .map((e) => ChatMessage(role: e['role'], content: e['content']))
              .toList(),
        ));
      }
      _current = sessions.first;
    }

    // Load config
    final cfg = await storage.loadConfig();
    final rawModels = (cfg['models'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    _models.clear();
    for (final m in rawModels) {
      _models.add(LlmModel(
        id: m['id'],
        provider: m['provider'],
        model: m['model'],
        apiKey: m['apiKey'],
        baseUrl: m['baseUrl'],
      ));
    }
    final selectedId = cfg['selectedModelId'] as String?;
    _activeModel = _models.where((m) => m.id == selectedId).cast<LlmModel?>().firstOrNull;
    _activeModel ??= _models.isNotEmpty ? _models.first : null;
    if (_activeModel != null) {
      await _persistConfig();
    }
    notifyListeners();
  }

  String _genId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> newSession() async {
    final s = ChatSession(id: _genId(), title: 'New Chat');
    sessions.insert(0, s);
    _current = s;
    notifyListeners();
  }

  Future<void> send(String text) async {
    if (_sending || text.trim().isEmpty || _current == null || _activeModel == null) return;
    _sending = true;
    _lastError = null;
    final cur = _current!;

    // Create pending user message but keep ability to rollback on cancel
    final userMsg = ChatMessage(role: 'user', content: text);
    cur.messages.add(userMsg);
    cur.title = (cur.title == 'New Chat' && text.isNotEmpty) ? text : cur.title;

    // Add waiting placeholder assistant message
    final placeholder = const ChatMessage(role: 'assistant', content: waitingPlaceholder);
    cur.messages.add(placeholder);
    notifyListeners();

    _cancelToken = CancellationToken();
    // Build turns excluding the waiting placeholder so it is not sent to APIs
    final turns = cur.messages
        .where((m) => (m.role == 'user' || m.role == 'assistant') && !(m.role == 'assistant' && m.content == waitingPlaceholder))
        .map((m) => ChatTurn(role: m.role, content: m.content))
        .toList();

    _sub = client
        .streamChat(
          turns: turns,
          model: _activeModel!,
          cancel: _cancelToken!,
        )
        .listen((chunk) {
      // Update last assistant message by appending tokens
      if (cur.messages.isNotEmpty && cur.messages.last.role == 'assistant') {
        final last = cur.messages.removeLast();
        final updated = ChatMessage(
          role: last.role,
          content: '${last.content == waitingPlaceholder ? '' : last.content}$chunk',
        );
        cur.messages.add(updated);
        notifyListeners();
      }
    }, onError: (e, st) {
      // Show error in status, rollback to pre-send state
      cur.messages.removeWhere((m) => m == placeholder || m == userMsg);
      cur.messages.add(const ChatMessage(role: 'status', content: 'Network error.'));
      _lastError = 'Network error.';
      _lastFailedPrompt = text;
      _sending = false;
      notifyListeners();
    }, onDone: () async {
      _sending = false;
      _cancelToken = null;
      _sub = null;
      await _persistSessions();
      notifyListeners();
    });
  }

  void cancel() {
    if (!_sending) return;
    _cancelToken?.cancel();
    _sub?.cancel();
    // Roll back last user + assistant placeholder
    final cur = _current!;
    if (cur.messages.isNotEmpty && cur.messages.last.role == 'assistant') {
      cur.messages.removeLast();
    }
    if (cur.messages.isNotEmpty && cur.messages.last.role == 'user') {
      cur.messages.removeLast();
    }
    if (cur.messages.isEmpty) {
      cur.title = 'New Chat';
    }
    _sending = false;
    notifyListeners();
  }

  void selectSession(ChatSession s) {
    _current = s;
    notifyListeners();
  }

  void setActiveModel(LlmModel model) {
    _activeModel = model;
    if (!_models.any((m) => m.id == model.id)) {
      _models.add(model);
    }
    _persistConfig();
    notifyListeners();
  }

  bool validateModel(LlmModel model) {
    if (model.provider == 'openai') {
      return model.model.trim().isNotEmpty && (model.apiKey != null && model.apiKey!.trim().isNotEmpty);
    }
    if (model.provider == 'ollama') {
      return model.model.trim().isNotEmpty && (model.baseUrl != null && model.baseUrl!.trim().isNotEmpty);
    }
    return false;
  }

  Future<bool> addModel(LlmModel model, {bool activate = true}) async {
    if (!validateModel(model)) return false;
    _models.removeWhere((m) => m.id == model.id);
    _models.add(model);
    if (activate) {
      _activeModel = model;
    }
    await _persistConfig();
    notifyListeners();
    return true;
  }

  Future<void> removeModel(String id) async {
    final isActive = _activeModel?.id == id;
    _models.removeWhere((m) => m.id == id);
    if (isActive) {
      _activeModel = _models.isNotEmpty ? _models.first : null;
    }
    await _persistConfig();
    notifyListeners();
  }

  Future<void> _persistSessions() async {
    final map = {
      'items': sessions
          .map((s) => {
                'id': s.id,
                'title': s.title,
                'messages': s.messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
              })
          .toList(),
    };
    await storage.saveSessions(map);
  }

  Future<void> _persistConfig() async {
    final map = {
      'models': _models
          .map((m) => {
                'id': m.id,
                'provider': m.provider,
                'model': m.model,
                'apiKey': m.apiKey,
                'baseUrl': m.baseUrl,
              })
          .toList(),
      'selectedModelId': _activeModel?.id,
    };
    await storage.saveConfig(map);
  }

  Future<void> deleteSessionAt(int index) async {
    if (index < 0 || index >= sessions.length) return;
    final removed = sessions.removeAt(index);
    if (identical(removed, _current)) {
      _current = sessions.isNotEmpty ? sessions.first : null;
    }
    await _persistSessions();
    notifyListeners();
  }

  Future<void> retryLast() async {
    if (_lastFailedPrompt != null && !_sending) {
      final prompt = _lastFailedPrompt!;
      await send(prompt);
    }
  }
}
