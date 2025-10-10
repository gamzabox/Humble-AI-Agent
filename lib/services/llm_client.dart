import 'dart:async';

class ChatTurn {
  final String role; // 'user' or 'assistant'
  final String content;
  ChatTurn({required this.role, required this.content});
}

class LlmModel {
  final String id; // display/unique id
  final String provider; // 'openai' or 'ollama'
  final String model; // model name
  final String? apiKey;
  final String? baseUrl;

  const LlmModel({
    required this.id,
    required this.provider,
    required this.model,
    this.apiKey,
    this.baseUrl,
  });
}

class CancellationToken {
  bool _cancelled = false;
  final Completer<void> _completer = Completer<void>();
  bool get isCancelled => _cancelled;
  Future<void> get onCancel => _completer.future;
  void cancel() {
    _cancelled = true;
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

abstract class LlmClient {
  Stream<String> streamChat({
    required List<ChatTurn> turns,
    required LlmModel model,
    required CancellationToken cancel,
  });
}
