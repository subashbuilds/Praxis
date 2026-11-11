/// Keep this in step with the version in pubspec.yaml. Release builds pass the
/// same value from pubspec through the Android build, so the About screen and
/// the package manager report one version.
const kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '2.3.0');
const kAppBuild = int.fromEnvironment('APP_BUILD', defaultValue: 6);

const kGitHubRepository = 'https://github.com/subashbuilds/Praxis';
const kGitHubRepositoryLabel = 'github.com/subashbuilds/Praxis';
