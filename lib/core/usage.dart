import 'dart:math' as math;

/// One model call's token accounting. Key material is never stored, only the
/// position of the key in the provider's list.
class UsageEvent {
  const UsageEvent({
    required this.at,
    required this.providerId,
    required this.providerName,
    required this.keyIndex,
    required this.model,
    required this.promptTokens,
    required this.completionTokens,
  });

  final DateTime at;
  final String providerId;
  final String providerName;
  final int keyIndex;
  final String model;
  final int promptTokens;
  final int completionTokens;

  int get tokens => promptTokens + completionTokens;
  String get keyLabel => 'key ${keyIndex + 1}';

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'providerId': providerId,
        'providerName': providerName,
        'keyIndex': keyIndex,
        'model': model,
        'prompt': promptTokens,
        'completion': completionTokens,
      };

  static UsageEvent? fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (at == null) return null;
    return UsageEvent(
      at: at,
      providerId: json['providerId'] as String? ?? '',
      providerName: json['providerName'] as String? ?? 'Provider',
      keyIndex: json['keyIndex'] as int? ?? 0,
      model: json['model'] as String? ?? '',
      promptTokens: json['prompt'] as int? ?? 0,
      completionTokens: json['completion'] as int? ?? 0,
    );
  }
}

class UsageDay {
  const UsageDay({required this.day, required this.tokens});
  final DateTime day;
  final int tokens;
}

class UsageProvider {
  const UsageProvider({
    required this.id,
    required this.name,
    required this.tokens,
    required this.keys,
    required this.models,
  });

  final String id;
  final String name;
  final int tokens;
  final List<UsageKey> keys;
  final List<UsageModel> models;
}

class UsageKey {
  const UsageKey({required this.index, required this.tokens});
  final int index;
  final int tokens;
  String get label => 'key ${index + 1}';
}

class UsageModel {
  const UsageModel({required this.name, required this.tokens});
  final String name;
  final int tokens;
}

class UsageStats {
  UsageStats(Iterable<UsageEvent> events)
      : events = List<UsageEvent>.unmodifiable(
          (events.toList()..sort((a, b) => b.at.compareTo(a.at))),
        );

  final List<UsageEvent> events;

  int get totalTokens => events.fold(0, (sum, event) => sum + event.tokens);
  int get promptTokens =>
      events.fold(0, (sum, event) => sum + event.promptTokens);
  int get completionTokens =>
      events.fold(0, (sum, event) => sum + event.completionTokens);

  int get todayTokens {
    final now = DateTime.now();
    return events
        .where((event) =>
            event.at.year == now.year &&
            event.at.month == now.month &&
            event.at.day == now.day)
        .fold(0, (sum, event) => sum + event.tokens);
  }

  UsageEvent? get latest => events.isEmpty ? null : events.first;

  UsageEvent? latestFor(String providerId, String model) {
    for (final event in events) {
      if (event.providerId == providerId && event.model == model) {
        return event;
      }
    }
    return null;
  }

  /// Seven calendar days ending today, oldest first. Empty days are zero, so
  /// the graph always has a stable shape.
  List<UsageDay> lastWeek() {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 6));
    final totals = <String, int>{};
    for (final event in events) {
      if (event.at.isBefore(start)) continue;
      final key = _dayKey(event.at);
      totals[key] = (totals[key] ?? 0) + event.tokens;
    }
    return List.generate(7, (index) {
      final day = start.add(Duration(days: index));
      return UsageDay(day: day, tokens: totals[_dayKey(day)] ?? 0);
    });
  }

  /// A stable 0–1 baseline for the graph, with a floor so a tiny day is still
  /// visible.
  double get weekPeak {
    final days = lastWeek();
    final peak = days.fold(0, (max, day) => math.max(max, day.tokens));
    return peak == 0 ? 1 : peak.toDouble();
  }

  List<UsageProvider> byProvider() {
    final byId = <String, Map<int, int>>{};
    final names = <String, String>{};
    final models = <String, Map<String, int>>{};
    for (final event in events) {
      final key = '${event.providerId}|${event.providerName}';
      names[key] = event.providerName;
      byId.putIfAbsent(key, () => {})[event.keyIndex] =
          (byId[key]![event.keyIndex] ?? 0) + event.tokens;
      final modelMap = models.putIfAbsent(key, () => {});
      final label = event.model.trim().isEmpty ? 'unknown model' : event.model;
      modelMap[label] = (modelMap[label] ?? 0) + event.tokens;
    }
    final result = <UsageProvider>[];
    for (final entry in byId.entries) {
      final providerId = entry.key.split('|').first;
      final keys = entry.value.entries
          .map((item) => UsageKey(index: item.key, tokens: item.value))
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      final modelList = (models[entry.key] ?? const <String, int>{})
          .entries
          .map((item) => UsageModel(name: item.key, tokens: item.value))
          .toList()
        ..sort((a, b) => b.tokens.compareTo(a.tokens));
      result.add(UsageProvider(
        id: providerId,
        name: names[entry.key] ?? 'Provider',
        tokens: entry.value.values.fold(0, (sum, value) => sum + value),
        keys: keys,
        models: modelList,
      ));
    }
    result.sort((a, b) => b.tokens.compareTo(a.tokens));
    return result;
  }

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String compactTokens(int tokens) {
  if (tokens < 1000) return '$tokens';
  if (tokens < 1000000) {
    final value = tokens / 1000;
    return '${value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}K';
  }
  final value = tokens / 1000000;
  return '${value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}M';
}
