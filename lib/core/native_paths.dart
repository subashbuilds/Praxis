import 'dart:io';

import 'package:flutter/services.dart';

/// Paths that only the Android embedding knows. Kept in one place so Linux
/// setup can be tested with a fake path and never has to guess the APK layout.
class NativePaths {
  const NativePaths._();

  static const _channel = MethodChannel('praxis/native');

  static Future<String?> nativeLibraryDir() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('nativeLibraryDir');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
