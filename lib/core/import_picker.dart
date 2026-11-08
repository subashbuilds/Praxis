import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Android's document picker hands back a SAF tree URI. Direct path access to
/// shared storage is blocked on modern Android, so the native side copies the
/// chosen tree into the app cache and returns a path Dart can actually read.
class ImportPicker {
  const ImportPicker._();

  static const _channel = MethodChannel('praxis/native');

  static Future<String?> pickFolder() async {
    if (!Platform.isAndroid) {
      return FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Import a folder',
      );
    }
    try {
      return await _channel.invokeMethod<String>('pickImportFolder');
    } on MissingPluginException {
      return FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Import a folder',
      );
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'The folder could not be read.');
    }
  }

  static Future<void> cleanup() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('clearImportCache');
    } catch (_) {
      // Cache cleanup is best effort and must never hide a successful import.
    }
  }
}
