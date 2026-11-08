import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Coding agents need room for reasoning plus a complete file edit. The old
/// 2048-token budget could be consumed entirely by a reasoning model before it
/// emitted its first tool call.
const kDefaultMaxOutputTokens = 8192;

class AiToolCall {
  const AiToolCall(
      {required this.id, required this.name, required this.arguments});

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class AiTurn {
  const AiTurn.user(this.text)
      : role = 'user',
        calls = const [],
        toolCallId = '',
        toolName = '';

  const AiTurn.assistant(this.text, this.calls)
      : role = 'assistant',
        toolCallId = '',
        toolName = '';

  const AiTurn.tool(this.toolCallId, this.toolName, this.text)
      : role = 'tool',
        calls = const [];

  final String role;
  final String text;
  final List<AiToolCall> calls;
  final String toolCallId;
  final String toolName;
}

class AiToolSpec {
  const AiToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
}

class AiUsage {
  const AiUsage({this.promptTokens = 0, this.completionTokens = 0});
  final int promptTokens;
  final int completionTokens;
  int get total => promptTokens + completionTokens;
}

class AiReply {
  const AiReply({
    required this.text,
    required this.calls,
    this.thinking = '',
    this.usage,
    this.finishReason = '',
  });
  final String text;
  final List<AiToolCall> calls;

  /// Reasoning returned by models that expose it (deepseek-reasoner,
  /// OpenRouter reasoning models, Anthropic thinking blocks).
  final String thinking;
  final AiUsage? usage;

  /// OpenAI's `finish_reason` or Anthropic's `stop_reason`. A reply cut off by
  /// the output budget must never be mistaken for a completed answer.
  final String finishReason;

  bool get hitOutputLimit =>
      finishReason == 'length' || finishReason == 'max_tokens';
}

typedef AiDelta = void Function(String delta);

class AiCancelledException implements Exception {
  const AiCancelledException();
}

class AiClient {
  AiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AiReply> complete({
    required ProviderConfig provider,
    required String system,
    required List<AiTurn> turns,
    required List<AiToolSpec> tools,
    int maxTokens = kDefaultMaxOutputTokens,
  }) async {
    final uri = _uriFor(provider);
    final http.Response response;
    try {
      response = await (provider.flavor == ApiFlavor.anthropic
              ? _anthropicRequest(
                  uri, provider, system, turns, tools, maxTokens)
              : _openAiRequest(uri, provider, system, turns, tools, maxTokens))
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw AiProviderException(
        '${provider.name} did not answer within 90s. Check the network and the base URL.',
      );
    } on http.ClientException catch (error) {
      throw AiProviderException(
          'Network error talking to ${provider.name}: ${error.message}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _failure(provider, response);
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AiProviderException(
          '${provider.name} returned a non-JSON response.');
    }

    return provider.flavor == ApiFlavor.anthropic
        ? _parseAnthropic(body)
        : _parseOpenAi(body);
  }

  /// Streams a completion. Text and reasoning arrive as they are produced;
  /// tool calls are assembled from their JSON fragments. Providers that answer
  /// with a plain JSON body are still supported.
  Future<AiReply> stream({
    required ProviderConfig provider,
    required String system,
    required List<AiTurn> turns,
    required List<AiToolSpec> tools,
    int maxTokens = kDefaultMaxOutputTokens,
    AiDelta? onText,
    AiDelta? onThinking,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) throw const AiCancelledException();
    final uri = _uriFor(provider);
    final request = http.Request('POST', uri);
    request.headers.addAll(_headers(provider));
    request.body = jsonEncode(provider.flavor == ApiFlavor.anthropic
        ? _anthropicPayload(provider, system, turns, tools, maxTokens,
            stream: true)
        : _openAiPayload(provider, system, turns, tools, maxTokens,
            stream: true));

    http.StreamedResponse response;
    try {
      response =
          await _client.send(request).timeout(const Duration(seconds: 45));
      if (isCancelled?.call() ?? false) {
        await response.stream.drain<void>();
        throw const AiCancelledException();
      }
    } on TimeoutException {
      throw AiProviderException(
          '${provider.name} did not start answering within 45s.');
    } on http.ClientException catch (error) {
      throw AiProviderException(
          'Network error talking to ${provider.name}: ${error.message}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw _failureFrom(provider, response.statusCode, body);
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('text/event-stream')) {
      final body = await response.stream.bytesToString();
      if (body.trimLeft().startsWith('data:')) {
        final reply = provider.flavor == ApiFlavor.anthropic
            ? await _consumeAnthropic(
                const Stream<String>.empty().cast<String>(),
                onText,
                onThinking,
                seeded: body,
                isCancelled: isCancelled,
              )
            : await _consumeOpenAi(
                const Stream<String>.empty().cast<String>(),
                onText,
                onThinking,
                seeded: body,
                isCancelled: isCancelled,
              );
        return reply;
      }
      Map<String, dynamic> json;
      try {
        json = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        throw AiProviderException(
            '${provider.name} returned an unreadable response.');
      }
      final reply = provider.flavor == ApiFlavor.anthropic
          ? _parseAnthropic(json)
          : _parseOpenAi(json);
      if (isCancelled?.call() ?? false) throw const AiCancelledException();
      if (reply.text.isNotEmpty) onText?.call(reply.text);
      if (reply.thinking.isNotEmpty) onThinking?.call(reply.thinking);
      return reply;
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 60));
    final controller = StreamController<String>();
    final subscription = lines.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    final cancellation = _cancellationSignal(isCancelled);
    try {
      final consumed = provider.flavor == ApiFlavor.anthropic
          ? _consumeAnthropic(
              controller.stream,
              onText,
              onThinking,
              isCancelled: isCancelled,
            )
          : _consumeOpenAi(
              controller.stream,
              onText,
              onThinking,
              isCancelled: isCancelled,
            );
      return await Future.any<AiReply>([
        consumed,
        cancellation.then<AiReply>((_) => throw const AiCancelledException()),
      ]);
    } on TimeoutException {
      throw AiProviderException(
          '${provider.name} stalled mid-response. Try again.');
    } finally {
      await subscription.cancel();
      if (!controller.isClosed) await controller.close();
    }
  }

  /// Completes when the agent's stop flag is raised. The stream subscription
  /// is cancelled by [stream] as soon as this wins the race, so a stop press
  /// does not wait for a provider to finish a long reply.
  Future<void> _cancellationSignal(bool Function()? isCancelled) {
    if (isCancelled == null) return Completer<void>().future;
    final completer = Completer<void>();
    Timer? timer;
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (isCancelled()) {
        timer?.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future.whenComplete(() => timer?.cancel());
  }

  /// Parses an already-buffered SSE body (used when a proxy omits the content
  /// type). Both consumers accept a seeded string for this case.
  Future<AiReply> _consumeOpenAi(
    Stream<String> lines,
    AiDelta? onText,
    AiDelta? onThinking, {
    String? seeded,
    bool Function()? isCancelled,
  }) async {
    final text = StringBuffer();
    final thinking = StringBuffer();
    final calls = <int, _CallBuilder>{};
    AiUsage? usage;
    var finishReason = '';

    Future<void> consume(String line) async {
      if (isCancelled?.call() ?? false) throw const AiCancelledException();
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) return;
      final data = trimmed.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') return;
      Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      if (json['error'] is Map) {
        final message =
            (json['error'] as Map)['message']?.toString() ?? 'Provider error';
        throw AiProviderException(message);
      }
      final rawUsage = json['usage'];
      if (rawUsage is Map) {
        usage = _usageFrom(rawUsage) ?? usage;
      }
      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) return;
      final choice = choices.first;
      if (choice is! Map) return;
      final rawFinish = choice['finish_reason'];
      if (rawFinish is String && rawFinish.isNotEmpty) {
        finishReason = rawFinish;
      }
      final delta = choice['delta'] ?? choice['message'];
      if (delta is! Map) return;
      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        text.write(content);
        onText?.call(content);
      }
      final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) {
        thinking.write(reasoning);
        onThinking?.call(reasoning);
      }
      final rawCalls = delta['tool_calls'];
      if (rawCalls is List) {
        for (var position = 0; position < rawCalls.length; position++) {
          final raw = rawCalls[position];
          if (raw is! Map) continue;
          final index = (raw['index'] as int?) ?? position;
          final builder = calls.putIfAbsent(index, _CallBuilder.new);
          if (raw['id'] is String) builder.id = raw['id'] as String;
          final function = raw['function'];
          if (function is Map) {
            if (function['name'] is String) {
              builder.name = function['name'] as String;
            }
            final args = function['arguments'];
            if (args is String) builder.arguments.write(args);
          }
        }
      }
    }

    if (seeded != null) {
      for (final line in const LineSplitter().convert(seeded)) {
        await consume(line);
      }
    }
    await for (final line in lines) {
      await consume(line);
    }

    final parsedCalls = <AiToolCall>[];
    for (final entry in (calls.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key)))) {
      final call = entry.value;
      if (call.name.isEmpty) continue;
      parsedCalls.add(AiToolCall(
        id: call.id.isEmpty ? 'call_${entry.key}' : call.id,
        name: call.name,
        arguments: _arguments(call.arguments.toString()),
      ));
    }
    return AiReply(
      text: text.toString().trim(),
      calls: parsedCalls,
      thinking: thinking.toString().trim(),
      usage: usage,
      finishReason: finishReason,
    );
  }

  Future<AiReply> _consumeAnthropic(
    Stream<String> lines,
    AiDelta? onText,
    AiDelta? onThinking, {
    String? seeded,
    bool Function()? isCancelled,
  }) async {
    final text = StringBuffer();
    final thinking = StringBuffer();
    final blocks = <int, _CallBuilder>{};
    var promptTokens = 0;
    var completionTokens = 0;
    var finishReason = '';

    Future<void> consume(String line) async {
      if (isCancelled?.call() ?? false) throw const AiCancelledException();
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) return;
      final data = trimmed.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') return;
      Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      final type = json['type'] as String? ?? '';
      switch (type) {
        case 'message_start':
          final message = json['message'];
          if (message is Map) {
            final usage = message['usage'];
            if (usage is Map) {
              promptTokens = usage['input_tokens'] as int? ?? promptTokens;
            }
          }
        case 'content_block_start':
          final index = json['index'] as int? ?? 0;
          final block = json['content_block'];
          if (block is Map && block['type'] == 'tool_use') {
            blocks[index] = _CallBuilder()
              ..id = block['id'] as String? ?? ''
              ..name = block['name'] as String? ?? '';
          }
        case 'content_block_delta':
          final index = json['index'] as int? ?? 0;
          final delta = json['delta'];
          if (delta is! Map) return;
          if (delta['type'] == 'text_delta') {
            final value = delta['text'] as String? ?? '';
            if (value.isNotEmpty) {
              text.write(value);
              onText?.call(value);
            }
          } else if (delta['type'] == 'thinking_delta') {
            final value = delta['thinking'] as String? ?? '';
            if (value.isNotEmpty) {
              thinking.write(value);
              onThinking?.call(value);
            }
          } else if (delta['type'] == 'input_json_delta') {
            final value = delta['partial_json'] as String? ?? '';
            blocks.putIfAbsent(index, _CallBuilder.new).arguments.write(value);
          }
        case 'message_delta':
          final delta = json['delta'];
          if (delta is Map && delta['stop_reason'] is String) {
            finishReason = delta['stop_reason'] as String;
          }
          final usage = json['usage'];
          if (usage is Map) {
            completionTokens =
                usage['output_tokens'] as int? ?? completionTokens;
          }
        case 'error':
          final error = json['error'];
          throw AiProviderException(
              error is Map ? '${error['message']}' : 'Provider error');
      }
    }

    if (seeded != null) {
      for (final line in const LineSplitter().convert(seeded)) {
        await consume(line);
      }
    }
    await for (final line in lines) {
      await consume(line);
    }

    final calls = <AiToolCall>[];
    for (final entry in (blocks.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key)))) {
      final call = entry.value;
      if (call.name.isEmpty) continue;
      calls.add(AiToolCall(
        id: call.id.isEmpty ? 'tool_${entry.key}' : call.id,
        name: call.name,
        arguments: _arguments(call.arguments.toString()),
      ));
    }
    return AiReply(
      text: text.toString().trim(),
      calls: calls,
      thinking: thinking.toString().trim(),
      usage: (promptTokens == 0 && completionTokens == 0)
          ? null
          : AiUsage(
              promptTokens: promptTokens,
              completionTokens: completionTokens,
            ),
      finishReason: finishReason,
    );
  }

  Uri _uriFor(ProviderConfig provider) {
    if (!provider.ready) {
      throw AiProviderException(
        'No API key saved for ${provider.name}. Open Settings → Providers and add one.',
        status: 401,
      );
    }
    if (provider.baseUrl.trim().isEmpty) {
      throw AiProviderException(
        'No base URL for ${provider.name}. Set one in Settings → Providers.',
      );
    }
    final base = provider.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final path = provider.flavor == ApiFlavor.anthropic
        ? '/messages'
        : '/chat/completions';
    final uri = Uri.tryParse('$base$path');
    if (uri == null || !uri.hasScheme) {
      throw AiProviderException('Invalid base URL: ${provider.baseUrl}');
    }
    return uri;
  }

  /// Lists the models the provider exposes to this key. Used by the provider
  /// form so the user can keep only the models they want.
  Future<List<String>> listModels(ProviderConfig provider) async {
    if (!provider.ready) {
      throw AiProviderException(
        'Add a key for ${provider.name} before fetching models.',
        status: 401,
      );
    }
    final base = provider.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base/models');
    if (uri == null || !uri.hasScheme) {
      throw AiProviderException('Invalid base URL: ${provider.baseUrl}');
    }
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: _headers(provider))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw AiProviderException(
        '${provider.name} did not answer the model list within 30s.',
      );
    } on http.ClientException catch (error) {
      throw AiProviderException(
          'Network error from ${provider.name}: ${error.message}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _failure(provider, response);
    }

    final List<dynamic> raw;
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['data'] is List) {
        raw = body['data'] as List;
      } else if (body is Map && body['models'] is List) {
        raw = body['models'] as List;
      } else if (body is List) {
        raw = body;
      } else {
        raw = const [];
      }
    } catch (_) {
      throw AiProviderException(
          '${provider.name} returned a model list that is not JSON.');
    }

    final models = <String>{};
    for (final item in raw) {
      if (item is String) {
        models.add(item.replaceFirst('models/', ''));
        continue;
      }
      if (item is Map) {
        final id = item['id'] ?? item['name'] ?? item['model'];
        if (id is String && id.trim().isNotEmpty) {
          models.add(id.replaceFirst('models/', '').trim());
        }
      }
    }
    final sorted = models.where((id) => id.isNotEmpty).toList()..sort();
    if (sorted.isEmpty) {
      throw AiProviderException(
        '${provider.name} returned no models. Check the base URL and key.',
      );
    }
    return sorted;
  }

  Map<String, String> _headers(ProviderConfig provider) => {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream, application/json',
        if (provider.flavor == ApiFlavor.anthropic)
          'x-api-key': provider.apiKey,
        if (provider.flavor == ApiFlavor.anthropic)
          'anthropic-version': '2023-06-01',
        if (provider.flavor != ApiFlavor.anthropic)
          'Authorization': 'Bearer ${provider.apiKey}',
        if (provider.id == 'openrouter') 'HTTP-Referer': 'https://praxis.app',
        if (provider.id == 'openrouter') 'X-Title': 'Praxis',
      };

  Future<http.Response> _openAiRequest(
    Uri uri,
    ProviderConfig provider,
    String system,
    List<AiTurn> turns,
    List<AiToolSpec> tools,
    int maxTokens,
  ) =>
      _client.post(
        uri,
        headers: _headers(provider),
        body: jsonEncode(
            _openAiPayload(provider, system, turns, tools, maxTokens)),
      );

  Map<String, dynamic> _openAiPayload(
    ProviderConfig provider,
    String system,
    List<AiTurn> turns,
    List<AiToolSpec> tools,
    int maxTokens, {
    bool stream = false,
  }) {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      for (final turn in turns) _openAiTurn(turn),
    ];
    return {
      'model': provider.model,
      'max_tokens': maxTokens,
      'temperature': 0.2,
      'messages': messages,
      'tools': tools
          .map((tool) => {
                'type': 'function',
                'function': {
                  'name': tool.name,
                  'description': tool.description,
                  'parameters': tool.parameters,
                },
              })
          .toList(),
      'tool_choice': 'auto',
      if (stream) 'stream': true,
      if (stream) 'stream_options': {'include_usage': true},
    };
  }

  Map<String, dynamic> _openAiTurn(AiTurn turn) {
    switch (turn.role) {
      case 'assistant':
        return {
          'role': 'assistant',
          'content': turn.text,
          if (turn.calls.isNotEmpty)
            'tool_calls': turn.calls
                .map((call) => {
                      'id': call.id,
                      'type': 'function',
                      'function': {
                        'name': call.name,
                        'arguments': jsonEncode(call.arguments),
                      },
                    })
                .toList(),
        };
      case 'tool':
        return {
          'role': 'tool',
          'tool_call_id': turn.toolCallId,
          'content': turn.text,
        };
      default:
        return {'role': 'user', 'content': turn.text};
    }
  }

  Future<http.Response> _anthropicRequest(
    Uri uri,
    ProviderConfig provider,
    String system,
    List<AiTurn> turns,
    List<AiToolSpec> tools,
    int maxTokens,
  ) =>
      _client.post(
        uri,
        headers: _headers(provider),
        body: jsonEncode(
            _anthropicPayload(provider, system, turns, tools, maxTokens)),
      );

  Map<String, dynamic> _anthropicPayload(
    ProviderConfig provider,
    String system,
    List<AiTurn> turns,
    List<AiToolSpec> tools,
    int maxTokens, {
    bool stream = false,
  }) {
    final messages = <Map<String, dynamic>>[];
    for (final turn in turns) {
      if (turn.role == 'tool') {
        final block = {
          'type': 'tool_result',
          'tool_use_id': turn.toolCallId,
          'content': turn.text,
        };
        if (messages.isNotEmpty &&
            messages.last['role'] == 'user' &&
            messages.last['content'] is List) {
          (messages.last['content'] as List).add(block);
        } else {
          messages.add({
            'role': 'user',
            'content': [block],
          });
        }
        continue;
      }
      if (turn.role == 'assistant') {
        final blocks = <Map<String, dynamic>>[
          if (turn.text.trim().isNotEmpty) {'type': 'text', 'text': turn.text},
          for (final call in turn.calls)
            {
              'type': 'tool_use',
              'id': call.id,
              'name': call.name,
              'input': call.arguments,
            },
        ];
        if (blocks.isEmpty) continue;
        messages.add({'role': 'assistant', 'content': blocks});
        continue;
      }
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': turn.text},
        ],
      });
    }
    return {
      'model': provider.model,
      'max_tokens': maxTokens,
      'system': system,
      'messages': messages,
      'tools': tools
          .map((tool) => {
                'name': tool.name,
                'description': tool.description,
                'input_schema': tool.parameters,
              })
          .toList(),
      if (stream) 'stream': true,
    };
  }

  AiReply _parseOpenAi(Map<String, dynamic> body) {
    final choices = body['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw AiProviderException('The provider returned no choices.');
    }
    final message =
        choices.first['message'] as Map<String, dynamic>? ?? const {};
    final text = (message['content'] as String?)?.trim() ?? '';
    final reasoning = message['reasoning_content'] ?? message['reasoning'];
    final thinking = reasoning is String ? reasoning.trim() : '';
    final calls = <AiToolCall>[];
    for (final raw in (message['tool_calls'] as List? ?? const [])) {
      final call = raw as Map<String, dynamic>;
      final function = call['function'] as Map<String, dynamic>? ?? const {};
      calls.add(AiToolCall(
        id: call['id'] as String? ?? 'call_${calls.length}',
        name: function['name'] as String? ?? '',
        arguments: _arguments(function['arguments']),
      ));
    }
    return AiReply(
      text: text,
      calls: calls,
      thinking: thinking,
      usage: _usageFrom(body['usage']),
      finishReason: choices.first['finish_reason'] as String? ?? '',
    );
  }

  AiReply _parseAnthropic(Map<String, dynamic> body) {
    final content = body['content'] as List? ?? const [];
    final buffer = StringBuffer();
    final reason = StringBuffer();
    final calls = <AiToolCall>[];
    for (final raw in content) {
      final block = raw as Map<String, dynamic>;
      if (block['type'] == 'text') {
        buffer.write(block['text'] as String? ?? '');
      } else if (block['type'] == 'thinking') {
        reason.write(block['thinking'] as String? ?? '');
      } else if (block['type'] == 'tool_use') {
        calls.add(AiToolCall(
          id: block['id'] as String? ?? 'tool_${calls.length}',
          name: block['name'] as String? ?? '',
          arguments:
              (block['input'] as Map?)?.cast<String, dynamic>() ?? const {},
        ));
      }
    }
    final usage = body['usage'];
    int prompt = 0;
    int completion = 0;
    if (usage is Map) {
      prompt = usage['input_tokens'] as int? ?? 0;
      completion = usage['output_tokens'] as int? ?? 0;
    }
    return AiReply(
      text: buffer.toString().trim(),
      calls: calls,
      thinking: reason.toString().trim(),
      usage: (prompt == 0 && completion == 0)
          ? null
          : AiUsage(promptTokens: prompt, completionTokens: completion),
      finishReason: body['stop_reason'] as String? ?? '',
    );
  }

  AiUsage? _usageFrom(Object? raw) {
    if (raw is! Map) return null;
    final prompt = raw['prompt_tokens'] ?? raw['input_tokens'];
    final completion = raw['completion_tokens'] ?? raw['output_tokens'];
    if (prompt is! int && completion is! int) return null;
    return AiUsage(
      promptTokens: prompt is int ? prompt : 0,
      completionTokens: completion is int ? completion : 0,
    );
  }

  Map<String, dynamic> _arguments(Object? raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        // fall through to empty args
      }
    }
    return const {};
  }

  AiProviderException _failure(
          ProviderConfig provider, http.Response response) =>
      _failureFrom(provider, response.statusCode, response.body);

  AiProviderException _failureFrom(
      ProviderConfig provider, int status, String body) {
    var detail = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          detail = error['message'] as String;
        } else if (error is String) {
          detail = error;
        } else if (decoded['message'] is String) {
          detail = decoded['message'] as String;
        }
      }
    } catch (_) {
      detail = body.length > 300 ? body.substring(0, 300) : body;
    }

    final hint = switch (status) {
      401 ||
      403 =>
        'API key rejected by ${provider.name}. Check the key in Settings → Providers.',
      402 =>
        '${provider.name} says the account is out of credit. Add credit or switch provider.',
      404 =>
        'Endpoint or model not found. Check the base URL and model name for ${provider.name}.',
      429 =>
        'Rate limited by ${provider.name}. If another key is saved, Praxis can switch to it.',
      400 => '${provider.name} rejected the request.',
      _ => '${provider.name} failed with HTTP $status.',
    };
    return AiProviderException(
      detail.isEmpty ? hint : '$hint\n$detail',
      status: status,
    );
  }
}

class _CallBuilder {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
