import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'store.dart';

enum BackgroundJobKind { agent, deploy }

enum BackgroundJobStatus { running, completed, failed, interrupted }

extension BackgroundJobStatusX on BackgroundJobStatus {
  String get label => switch (this) {
        BackgroundJobStatus.running => 'Running',
        BackgroundJobStatus.completed => 'Completed',
        BackgroundJobStatus.failed => 'Failed',
        BackgroundJobStatus.interrupted => 'Interrupted',
      };

  bool get active => this == BackgroundJobStatus.running;
}

/// A small durable record for a long-running agent task or deployment. It
/// stores status, not the work itself: the task checkpoint and the deployment
/// result remain the source of truth. Keeping this journal means the UI can
/// explain what happened after Android restarts the process instead of losing
/// the job silently.
class BackgroundJobRecord {
  const BackgroundJobRecord({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.kind,
    required this.title,
    required this.startedAt,
    required this.updatedAt,
    this.detail = '',
    this.status = BackgroundJobStatus.running,
    this.data = const {},
  });

  final String id;
  final String projectId;
  final String projectName;
  final BackgroundJobKind kind;
  final String title;
  final String detail;
  final BackgroundJobStatus status;
  final DateTime startedAt;
  final DateTime updatedAt;

  /// Kind-specific recovery data. It must never contain prompts, file
  /// contents, credentials or tool output.
  final Map<String, dynamic> data;

  bool get running => status == BackgroundJobStatus.running;

  BackgroundJobRecord copyWith({
    String? detail,
    BackgroundJobStatus? status,
    DateTime? updatedAt,
  }) =>
      BackgroundJobRecord(
        id: id,
        projectId: projectId,
        projectName: projectName,
        kind: kind,
        title: title,
        detail: detail ?? this.detail,
        status: status ?? this.status,
        startedAt: startedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        data: data,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'kind': kind.name,
        'title': title,
        'detail': detail,
        'status': status.name,
        'startedAt': startedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'data': data,
      };

  static BackgroundJobRecord? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final projectId = json['projectId'] as String? ?? '';
    if (id.isEmpty || projectId.isEmpty) return null;
    final kind = BackgroundJobKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => BackgroundJobKind.agent,
    );
    final status = BackgroundJobStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => BackgroundJobStatus.interrupted,
    );
    final startedAt =
        DateTime.tryParse(json['startedAt'] as String? ?? '') ?? DateTime.now();
    return BackgroundJobRecord(
      id: id,
      projectId: projectId,
      projectName: json['projectName'] as String? ?? 'Project',
      kind: kind,
      title: (json['title'] as String? ?? '').trim().isEmpty
          ? 'Background job'
          : json['title'] as String,
      detail: json['detail'] as String? ?? '',
      status: status,
      startedAt: startedAt,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? startedAt,
      data: json['data'] is Map
          ? (json['data'] as Map).map(
              (key, value) => MapEntry('$key', value),
            )
          : const {},
    );
  }
}

/// Persists the job journal. Running jobs found on a fresh process are marked
/// interrupted: Dart execution cannot continue after Android kills the app.
/// A resumable agent checkpoint remains available, and a deploy can be retried
/// from the project.
class BackgroundJobJournal {
  BackgroundJobJournal(this.store);

  static const key = 'praxis.backgroundJobs';
  static const _limit = 30;

  final KVStore store;
  final List<BackgroundJobRecord> items = [];
  Future<void> _write = Future.value();

  Future<void> load() async {
    items.clear();
    final raw = store.read(key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            final record =
                BackgroundJobRecord.fromJson(item.cast<String, dynamic>());
            if (record != null) items.add(record);
          }
        }
      } catch (_) {
        // A corrupt journal must not keep the workbench from starting.
      }
    }

    var recovered = false;
    for (var index = 0; index < items.length; index++) {
      if (!items[index].running) continue;
      items[index] = items[index].copyWith(
        status: BackgroundJobStatus.interrupted,
        detail: 'Praxis closed before this job finished.',
        updatedAt: DateTime.now(),
      );
      recovered = true;
    }
    _sort();
    if (recovered) await flush();
  }

  void upsert(BackgroundJobRecord record, {bool persist = true}) {
    final index = items.indexWhere((item) => item.id == record.id);
    if (index >= 0) {
      items[index] = record;
    } else {
      items.add(record);
      while (items.length > _limit) {
        final finished = items.indexWhere((item) => !item.running);
        if (finished < 0) break;
        items.removeAt(finished);
      }
    }
    _sort();
    if (persist) _scheduleSave();
  }

  void remove(String id) {
    items.removeWhere((item) => item.id == id);
    _scheduleSave();
  }

  void clearFinished() {
    items.removeWhere((item) => !item.running);
    _scheduleSave();
  }

  Future<void> flush() {
    final payload = jsonEncode(items.map((item) => item.toJson()).toList());
    _write = _write.then((_) => store.write(key, payload));
    return _write;
  }

  void _scheduleSave() {
    final payload = jsonEncode(items.map((item) => item.toJson()).toList());
    _write = _write.then((_) => store.write(key, payload));
  }

  void _sort() => items.sort((a, b) => b.startedAt.compareTo(a.startedAt));
}

/// Thin platform bridge to the Android foreground service. On a desktop test
/// run there is no plugin, which is harmless: the journal still works.
class BackgroundJobPlatform {
  static const _channel = MethodChannel('praxis/background_jobs');

  Future<void> start({
    required String title,
    required String detail,
  }) async {
    await _invoke('start', {'title': title, 'detail': detail});
  }

  Future<void> update({
    required String title,
    required String detail,
  }) async {
    await _invoke('update', {'title': title, 'detail': detail});
  }

  Future<void> stop() => _invoke('stop', const {});

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    // The service exists only on Android. Skipping elsewhere also keeps pure
    // Dart tests from touching a method channel before a Flutter binding is
    // initialized.
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Desktop and widget tests do not register the native service.
    } on PlatformException {
      // A notification failure must never fail the actual build or agent task.
    }
  }
}
