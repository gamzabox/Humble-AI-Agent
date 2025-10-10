import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_client.dart';

class RoutingLlmClient implements LlmClient {
  final http.Client _http;
  RoutingLlmClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  @override
  Stream<String> streamChat({
    required List<ChatTurn> turns,
    required LlmModel model,
    required CancellationToken cancel,
  }) async* {
    if (model.provider == 'openai') {
      yield* _openAiStream(turns: turns, model: model, cancel: cancel);
    } else if (model.provider == 'ollama') {
      yield* _ollamaStream(turns: turns, model: model, cancel: cancel);
    } else {
      throw UnsupportedError('Unknown provider: ${model.provider}');
    }
  }

  Stream<String> _openAiStream({
    required List<ChatTurn> turns,
    required LlmModel model,
    required CancellationToken cancel,
  }) async* {
    final uri = Uri.parse((model.baseUrl?.isNotEmpty ?? false)
        ? model.baseUrl!
        : 'https://api.openai.com/v1/chat/completions');
    final req = http.Request('POST', uri);
    req.headers.addAll({
      'Content-Type': 'application/json',
      if ((model.apiKey ?? '').isNotEmpty) 'Authorization': 'Bearer ${model.apiKey}',
    });

    req.body = jsonEncode({
      'model': model.model,
      'stream': true,
      'messages': turns
          .map((t) => {
                'role': t.role,
                'content': t.content,
              })
          .toList(),
    });

    final resp = await _http.send(req);
    final stream = resp.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final sub = StreamController<String>();

    // Cancellation: cancel subscription when token resolves
    cancel.onCancel.then((_) {
      sub.close();
    });

    stream.listen((line) {
      if (line.isEmpty) return;
      if (line.startsWith('data:')) {
        final data = line.substring(5).trim();
        if (data == '[DONE]') {
          sub.close();
          return;
        }
        try {
          final obj = jsonDecode(data) as Map<String, dynamic>;
          final choices = obj['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final delta = (choices.first as Map)['delta'] as Map?;
            final chunk = (delta?['content'] as String?) ?? '';
            if (chunk.isNotEmpty) sub.add(chunk);
          }
        } catch (_) {}
      }
    }, onError: (e, st) {
      sub.addError(e, st);
      sub.close();
    }, onDone: () {
      sub.close();
    });

    yield* sub.stream;
  }

  Stream<String> _ollamaStream({
    required List<ChatTurn> turns,
    required LlmModel model,
    required CancellationToken cancel,
  }) async* {
    final base = model.baseUrl ?? 'http://localhost:11434';
    final uri = Uri.parse('$base/api/chat');
    final req = http.Request('POST', uri);
    req.headers.addAll({'Content-Type': 'application/json'});
    req.body = jsonEncode({
      'model': model.model,
      'stream': true,
      'messages': turns
          .map((t) => {
                'role': t.role,
                'content': t.content,
              })
          .toList(),
    });

    final resp = await _http.send(req);
    final stream = resp.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final controller = StreamController<String>();
    cancel.onCancel.then((_) => controller.close());

    stream.listen((line) {
      if (line.isEmpty) return;
      try {
        final obj = jsonDecode(line) as Map<String, dynamic>;
        if ((obj['done'] as bool?) == true) {
          controller.close();
          return;
        }
        final msg = obj['message'] as Map<String, dynamic>?;
        final chunk = msg?['content'] as String? ?? obj['response'] as String? ?? '';
        if (chunk.isNotEmpty) controller.add(chunk);
      } catch (_) {}
    }, onError: (e, st) {
      controller.addError(e, st);
      controller.close();
    }, onDone: () {
      controller.close();
    });

    yield* controller.stream;
  }
}

