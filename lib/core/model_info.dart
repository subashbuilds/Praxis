/// Context windows for the model families Praxis can reach. The list is
/// deliberately conservative: when a model is unknown we return null instead
/// of inventing a limit.
int? contextWindowFor(String model) {
  final name = model.toLowerCase().trim();
  if (name.isEmpty) return null;

  // OpenAI
  if (name.contains('gpt-4.1')) return 1047576;
  if (name.contains('gpt-4o')) return 128000;
  if (name.contains('gpt-4-turbo') || name.contains('gpt-4-1106')) {
    return 128000;
  }
  if (name.startsWith('gpt-4')) return 8192;
  if (name.contains('gpt-3.5')) return 16385;
  if (name.startsWith('o1') ||
      name.startsWith('o3') ||
      name.startsWith('o4') ||
      name.contains('o3-mini')) {
    return 200000;
  }

  // Anthropic
  if (name.contains('claude')) return 200000;

  // Google
  if (name.contains('gemini-1.5-pro')) return 2097152;
  if (name.contains('gemini')) return 1048576;

  // Open-weight families
  if (name.contains('deepseek')) return 65536;
  if (name.contains('nemotron')) return 131072;
  if (name.contains('llama')) return 131072;
  if (name.contains('mistral') ||
      name.contains('mixtral') ||
      name.contains('codestral') ||
      name.contains('devstral')) {
    return 131072;
  }
  if (name.contains('qwen')) return 131072;
  if (name.contains('grok')) return 131072;
  if (name.contains('command-r')) return 131072;
  if (name.contains('phi-4')) return 131072;
  if (name.contains('gemma')) return 131072;

  return null;
}

String contextLabel(String model, int? used) {
  final limit = contextWindowFor(model);
  if (limit == null) {
    return used == null ? 'context unknown' : '${_short(used)} used';
  }
  if (used == null) return _short(limit);
  return '${_short(used)}/${_short(limit)}';
}

String _short(int tokens) {
  if (tokens < 1000) return '$tokens';
  if (tokens < 1000000) {
    final value = tokens / 1000;
    return '${value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(0)}K';
  }
  final value = tokens / 1000000;
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}M';
}
