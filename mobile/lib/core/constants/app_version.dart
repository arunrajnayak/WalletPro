class AppVersion {
  /// Current runtime app semantic version (must match mobile/pubspec.yaml)
  static const String version = '1.10.0';

  /// Current build number
  static const int buildNumber = 21;

  /// GitHub repository slug
  static const String repoOwner = 'arunrajnayak';
  static const String repoName = 'WalletPro';

  /// Full GitHub releases API endpoint
  static const String latestReleaseUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
}
