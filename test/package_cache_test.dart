import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/package_cache.dart';

void main() {
  test('partial node_modules is never reused without a finished install marker',
      () {
    expect(
      npmInstallReusable(
        hasNodeModules: true,
        hasNpmLock: false,
        markerFingerprint: null,
        fingerprint: 'manifest-a',
      ),
      isFalse,
    );
    expect(
      npmInstallReusable(
        hasNodeModules: true,
        hasNpmLock: true,
        markerFingerprint: 'manifest-a',
        fingerprint: 'manifest-a',
      ),
      isTrue,
    );
    expect(
      npmInstallReusable(
        hasNodeModules: true,
        hasNpmLock: true,
        markerFingerprint: 'manifest-a',
        fingerprint: 'manifest-b',
      ),
      isFalse,
    );
  });

  test('npm cache lists a package once with its version and delete keys', () {
    final packages = parseNpmCache('''
make-fetch-happen:request-cache:https://registry.npmjs.org/left-pad
make-fetch-happen:request-cache:https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz
pacote:tarball:left-pad@1.3.0
make-fetch-happen:request-cache:https://registry.npmjs.org/@scope/tool/-/tool-2.4.1.tgz
''');

    expect(packages, hasLength(2));
    final leftPad = packages.firstWhere((item) => item.name == 'left-pad');
    expect(leftPad.version, '1.3.0');
    expect(leftPad.runtime, PackageCacheRuntime.npm);
    expect(leftPad.keys, hasLength(1));
    expect(leftPad.keys.single, contains('left-pad-1.3.0.tgz'));
    expect(
      packages.firstWhere((item) => item.name == '@scope/tool').version,
      '2.4.1',
    );
  });

  test('pip cache groups wheel and source archives for the same package', () {
    final packages = parsePipCache('''
/root/.cache/pip/wheels/requests-2.31.0-py3-none-any.whl
/root/.cache/pip/wheels/requests-2.30.0-py3-none-any.whl
/root/.cache/pip/http/pytest-8.0.0.tar.gz
not-a-package.txt
''');

    expect(packages, hasLength(3));
    final requests = packages.firstWhere((item) => item.name == 'requests');
    expect(requests.version, '2.31.0');
    expect(requests.runtime, PackageCacheRuntime.python);
    expect(requests.keys.single, endsWith('requests-2.31.0-py3-none-any.whl'));
    expect(
      packages.firstWhere((item) => item.name == 'pytest').version,
      '8.0.0',
    );
  });
}
