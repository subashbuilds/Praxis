import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

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

class AiReply {
  const AiReply({
    required this.text,
    required this.calls,
    this.thinking = '',
  });
  final String text;
  final List<AiToolCall> calls;

  /// Reasoning returned by models that expose it (deepseek-reasoner,
  /// OpenRouter reasoning models, Anthropic thinking blocks).
  final String thinking;
}

class AiClient {
  AiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AiReply> complete({
    required ProviderConfig provider,
    required String system,
    required List<AiTurn> turns,
    required List<AiToolSpec> tools,
    int maxTokens = 2048,
  }) async {
    if (!provider.ready) {
      throw AiProviderException(
        'No API key saved for ${provider.name}. Open Settings → Models and add one.',
        status: 401,
      );
    }
    if (provider.baseUrl.trim().isEmpty) {
      throw AiProviderException(
        'No base URL for ${provider.name}. Set one in Settings → Models.',
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
      response = await _client.get(
        uri,
        headers: {
          if (provider.flavor == ApiFlavor.anthropic)
            'x-api-key': provider.apiKey,
          if (provider.flavor == ApiFlavor.anthropic)
            'anthropic-version': '2023-06-01',
          if (provider.flavor != ApiFlavor.anthropic)
            'Authorization': 'Bearer ${provider.apiKey}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));
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

  Future<http.Response> _openAiRequest(
    Uri uri,
    ProviderConfig provider,
    String system,
    List<AiTurn> turns,
    List<AiToolSpec> tools,
    int maxTokens,
  ) {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
      for (final turn in turns) _openAiTurn(turn),
    ];
    return _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${provider.apiKey}',
        if (provider.id == 'openrouter') 'HTTP-Referer': 'https://devnest.app',
        if (provider.id == 'openrouter') 'X-Title': 'DevNest',
      },
      body: jsonEncode({
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
      }),
    );
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
  ) {
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
            'content': [block]
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

    return _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': provider.apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
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
      }),
    );
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
    return AiReply(text: text, calls: calls, thinking: thinking);
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
    return AiReply(
      text: buffer.toString().trim(),
      calls: calls,
      thinking: reason.toString().trim(),
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
      ProviderConfig provider, http.Response response) {
    var detail = '';
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final error = body['error'];
        if (error is Map && error['message'] is String) {
          detail = error['message'] as String;
        } else if (error is String) {
          detail = error;
        } else if (body['message'] is String) {
          detail = body['message'] as String;
        }
      }
    } catch (_) {
      detail = response.body.length > 300
          ? response.body.substring(0, 300)
          : response.body;
    }

    final hint = switch (response.statusCode) {
      401 ||
      403 =>
        'API key rejected by ${provider.name}. Check the key in Settings → Models.',
      402 =>
        '${provider.name} says the account is out of credit. Add credit or switch provider.',
      404 =>
        'Endpoint or model not found. Check the base URL and model name for ${provider.name}.',
      429 =>
        'Rate limited by ${provider.name}. If another key is saved, DevNest can switch to it.',
      400 => '${provider.name} rejected the request.',
      _ => '${provider.name} failed with HTTP ${response.statusCode}.',
    };
    return AiProviderException(
      detail.isEmpty ? hint : '$hint\n$detail',
      status: response.statusCode,
    );
  }
}
