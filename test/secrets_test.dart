import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/secrets.dart';
import 'package:praxis/core/store.dart';

class _FakeSealer implements SecretSealer {
  _FakeSealer({this.working = true});

  final bool working;
  int sealed = 0;

  @override
  Future<String?> seal(String plain) async {
    if (!working) return null;
    sealed++;
    return base64Encode(utf8.encode('sealed::$plain'));
  }

  @override
  Future<String?> open(String value) async {
    if (!working) return null;
    final text = utf8.decode(base64Decode(value));
    return text.startsWith('sealed::') ? text.substring(8) : null;
  }
}

void main() {
  test('a sealed secret round-trips and is not stored as plaintext', () async {
    final store = MemoryStore();
    final vault = SecretsVault(store, sealer: _FakeSealer());

    await vault.write('praxis.providers', '{"key":"sk-secret-value"}');

    final raw = store.read('praxis.providers')!;
    expect(raw, startsWith(SecretsVault.sealedPrefix));
    expect(raw.contains('sk-secret-value'), isFalse);
    expect(await vault.read('praxis.providers'), '{"key":"sk-secret-value"}');
  });

  test('plaintext written by an older build still loads', () async {
    final store = MemoryStore({'praxis.integrations': '{"token":"old"}'});
    final vault = SecretsVault(store, sealer: _FakeSealer());

    expect(await vault.read('praxis.integrations'), '{"token":"old"}');
  });

  test('upgrade seals a legacy value in place', () async {
    final store = MemoryStore({'praxis.integrations': '{"token":"old"}'});
    final vault = SecretsVault(store, sealer: _FakeSealer());

    expect(await vault.upgrade('praxis.integrations'), isTrue);
    expect(store.read('praxis.integrations'),
        startsWith(SecretsVault.sealedPrefix));
    expect(await vault.read('praxis.integrations'), '{"token":"old"}');
    // Running it again is a no-op.
    expect(await vault.upgrade('praxis.integrations'), isFalse);
  });

  test('a device without a keystore keeps working without losing data',
      () async {
    final store = MemoryStore();
    final vault = SecretsVault(store, sealer: _FakeSealer(working: false));

    await vault.write('praxis.providers', '{"key":"sk-live"}');

    expect(vault.lastWriteSealed, isFalse);
    expect(store.read('praxis.providers'), '{"key":"sk-live"}');
    expect(await vault.read('praxis.providers'), '{"key":"sk-live"}');
  });

  test('a sealed value that cannot be opened is left in place', () async {
    final store = MemoryStore();
    final vault = SecretsVault(store, sealer: _FakeSealer());
    await vault.write('praxis.providers', '{"key":"sk-live"}');
    final sealed = store.read('praxis.providers');

    final broken = SecretsVault(store, sealer: _FakeSealer(working: false));
    expect(await broken.read('praxis.providers'), isNull);
    // Overwriting it would destroy a key that another install can still open.
    expect(store.read('praxis.providers'), sealed);
  });
}
