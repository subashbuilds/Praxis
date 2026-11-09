import 'dart:math' as math;

import '../models.dart';

/// A local estimate of how many model requests a provider has answered today.
///
/// This is deliberately separate from token usage: a provider can bill by
/// request, and a failed request still consumes a free-tier slot. The count is
/// only an estimate. Provider dashboards remain authoritative.
class QuotaTracker {
  QuotaTracker({Map<String, int>? counts, DateTime Function()? clock})
      : _counts = {...?counts},
        _clock = clock ?? DateTime.now;

  final Map<String, int> _counts;
  final DateTime Function() _clock;

  static String dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _key(String providerId, DateTime day) => '$providerId@${dayKey(day)}';

  int usedToday(String providerId) => _counts[_key(providerId, _clock())] ?? 0;

  int record(String providerId) {
    final now = _clock();
    final key = _key(providerId, now);
    final next = (_counts[key] ?? 0) + 1;
    _counts[key] = next;
    prune(now: now);
    return next;
  }

  QuotaStatus status(ProviderConfig provider) => QuotaStatus(
        providerId: provider.id,
        used: usedToday(provider.id),
        limit: provider.dailyLimit,
      );

  /// Keeps a week of local history so a count is never lost around midnight
  /// when the clock and a provider's own reset boundary differ.
  void prune({DateTime? now}) {
    final today = now ?? _clock();
    final cutoff = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 7));
    _counts.removeWhere((key, _) {
      final at = key.lastIndexOf('@');
      if (at < 0) return true;
      final day = DateTime.tryParse(key.substring(at + 1));
      return day == null || day.isBefore(cutoff);
    });
  }

  Map<String, int> toJson() {
    prune();
    final keys = _counts.keys.toList()..sort();
    return {for (final key in keys) key: _counts[key]!};
  }

  static QuotaTracker fromJson(Object? raw, {DateTime Function()? clock}) {
    final counts = <String, int>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (entry.key is String && value is int && value >= 0) {
          counts[entry.key as String] = value;
        }
      }
    }
    return QuotaTracker(counts: counts, clock: clock);
  }
}

class QuotaStatus {
  const QuotaStatus({
    required this.providerId,
    required this.used,
    required this.limit,
  });

  final String providerId;
  final int used;

  /// Zero means the user has not set a limit. No provider limit is hardcoded.
  final int limit;

  bool get hasLimit => limit > 0;
  int get remaining => hasLimit ? math.max(0, limit - used) : 0;
  bool get exhausted => hasLimit && used >= limit;
  double get fraction => hasLimit ? (used / limit).clamp(0.0, 1.0) : 0.0;

  /// At or above 80% the UI turns amber. The user's value is authoritative.
  bool get warning => hasLimit && used >= (limit * 0.8).ceil() && !exhausted;

  /// Low means at most one request, or the final fifth of the allowance.
  bool get low {
    if (!hasLimit || exhausted) return false;
    final lowThreshold = math.max(1, (limit * 0.2).ceil());
    return remaining <= lowThreshold;
  }

  String get label => hasLimit
      ? '$used/$limit requests used today'
      : '$used requests used today';

  String get remainingLabel => hasLimit
      ? '$remaining ${remaining == 1 ? 'request' : 'requests'} left today'
      : 'No daily limit set';
}
