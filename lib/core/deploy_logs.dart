import 'dart:convert';

import 'vfs.dart';

/// The last deploy result for a project. Logs stored here are already masked,
/// but loaders mask again in case the project's secret values changed.
class LastDeployLog {
  const LastDeployLog({
    required this.runtime,
    required this.message,
    required this.logs,
    required this.at,
    this.url = '',
    this.deploymentId = '',
    this.success = true,
  });

  final String runtime;
  final String message;
  final String logs;
  final DateTime at;
  final String url;
  final String deploymentId;
  final bool success;

  LastDeployLog copyWith({
    String? runtime,
    String? message,
    String? logs,
    DateTime? at,
    String? url,
    String? deploymentId,
    bool? success,
  }) =>
      LastDeployLog(
        runtime: runtime ?? this.runtime,
        message: message ?? this.message,
        logs: logs ?? this.logs,
        at: at ?? this.at,
        url: url ?? this.url,
        deploymentId: deploymentId ?? this.deploymentId,
        success: success ?? this.success,
      );

  Map<String, dynamic> toJson() => {
        'runtime': runtime,
        'message': message,
        'logs': logs,
        'at': at.toUtc().toIso8601String(),
        'url': url,
        'deploymentId': deploymentId,
        'success': success,
      };

  static LastDeployLog? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at'] ?? ''}');
    if (at == null) return null;
    return LastDeployLog(
      runtime: '${json['runtime'] ?? 'Deploy'}',
      message: '${json['message'] ?? ''}',
      logs: '${json['logs'] ?? ''}',
      at: at,
      url: '${json['url'] ?? ''}',
      deploymentId: '${json['deploymentId'] ?? ''}',
      success: json['success'] != false,
    );
  }
}

class DeployLogStore {
  const DeployLogStore._();

  static const path = '.praxis/last_deploy.json';

  static Future<LastDeployLog?> load(ProjectFs fs) async {
    try {
      if (!await fs.exists(path)) return null;
      return LastDeployLog.fromJson(jsonDecode(await fs.read(path)));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(ProjectFs fs, LastDeployLog record) =>
      fs.write(path, jsonEncode(record.toJson()));
}
