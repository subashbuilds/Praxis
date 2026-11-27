import 'package:flutter/services.dart';

import 'store.dart';

/// Seals and opens short secrets with a key the app cannot read back. Returns
/// null when the platform has no keystore (tests, desktop dev), which keeps the
/// caller working instead of failing its save.
abstract class SecretSealer {
  Future<String?> seal(String plain);
  Future<String?> open(String sealed);
}

/// Android Keystore AES/GCM. The key is generated on first use, never leaves
/// the keystore and is not included in backups.
class KeystoreSecretSealer implements SecretSealer {
  const KeystoreSecretSealer();

  static const channel = MethodChannel('praxis/native');

  @override
  Future<String?> seal(String plain) async {
    try {
      return await channel.invokeMethod<String>('sealSecret', {'value': plain});
    } catch (_) {
      // No platform channel, no binding or a keystore failure: the caller
      // keeps working and records that the value was stored unsealed.
      return null;
    }
  }

  @override
  Future<String?> open(String sealed) async {
    try {
      return await channel
          .invokeMethod<String>('openSecret', {'value': sealed});
    } catch (_) {
      return null;
    }
  }
}

/// Stores provider keys and integration tokens sealed at rest.
///
/// The value in [KVStore] is a `praxis.sealed.v1:` marker followed by the
/// keystore ciphertext. Older builds wrote plaintext; [read] returns it
/// unchanged and [upgrade] replaces it in place, so an upgrade needs no user
/// action.
class SecretsVault {
  SecretsVault(this.store, {SecretSealer? sealer})
      : sealer = sealer ?? const KeystoreSecretSealer();

  final KVStore store;
  final SecretSealer sealer;

  static const sealedPrefix = 'praxis.sealed.v1:';

  static bool _isSealed(String raw) => raw.startsWith(sealedPrefix);

  /// Returns the plaintext for [key], or null when nothing is stored or the
  /// value cannot be opened on this device. A value that cannot be opened is
  /// left in place: overwriting it would destroy a key the user may still be
  /// able to recover on the device that sealed it.
  Future<String?> read(String key) async {
    final raw = store.read(key);
    if (raw == null) return null;
    if (!_isSealed(raw)) return raw;
    return sealer.open(raw.substring(sealedPrefix.length));
  }

  Future<void> write(String key, String value) async {
    final sealed = await sealer.seal(value);
    await store.write(
      key,
      sealed == null ? value : '$sealedPrefix$sealed',
    );
  }

  /// Seals a value an older build stored as plaintext. Returns true when the
  /// stored value changed.
  Future<bool> upgrade(String key) async {
    final raw = store.read(key);
    if (raw == null || _isSealed(raw)) return false;
    final sealed = await sealer.seal(raw);
    if (sealed == null) return false;
    await store.write(key, '$sealedPrefix$sealed');
    return true;
  }
}
