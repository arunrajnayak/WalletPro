import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_version.dart';
import '../remote/api_client.dart';

class UpdateInfo {
  final String tagName;
  final String version;
  final String title;
  final String changelog;
  final String apkDownloadUrl;
  final int apkSize;
  final DateTime? publishedAt;
  final bool isUpdateAvailable;

  UpdateInfo({
    required this.tagName,
    required this.version,
    required this.title,
    required this.changelog,
    required this.apkDownloadUrl,
    required this.apkSize,
    this.publishedAt,
    required this.isUpdateAvailable,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {String? currentVersion}) {
    final rawTag = (json['tagName'] ?? json['tag_name'] ?? '').toString();
    final cleanVersion = rawTag.replaceAll(RegExp(r'^v'), '').trim();
    final appVer = currentVersion ?? AppVersion.version;

    final assets = json['assets'] as List<dynamic>?;
    String apkUrl = (json['apkDownloadUrl'] ?? '').toString();
    int size = (json['apkSize'] as num?)?.toInt() ?? 0;

    if (apkUrl.isEmpty && assets != null && assets.isNotEmpty) {
      final apkAsset = assets.firstWhere(
        (a) => (a['name']?.toString().endsWith('.apk') ?? false) ||
            a['content_type'] == 'application/vnd.android.package-archive',
        orElse: () => assets.first,
      );
      apkUrl = apkAsset['browser_download_url'] ?? '';
      size = (apkAsset['size'] as num?)?.toInt() ?? 0;
    }

    final publishedStr = (json['publishedAt'] ?? json['published_at'])?.toString();
    DateTime? pubDate;
    if (publishedStr != null && publishedStr.isNotEmpty) {
      pubDate = DateTime.tryParse(publishedStr);
    }

    final isNewer = UpdateService.compareVersions(cleanVersion, appVer) > 0;

    return UpdateInfo(
      tagName: rawTag.isNotEmpty ? rawTag : 'v$cleanVersion',
      version: cleanVersion,
      title: (json['name'] ?? json['title'] ?? 'WalletPro v$cleanVersion').toString(),
      changelog: (json['body'] ?? '').toString().trim(),
      apkDownloadUrl: apkUrl,
      apkSize: size,
      publishedAt: pubDate,
      isUpdateAvailable: isNewer,
    );
  }
}

class UpdateService {
  static const MethodChannel _updatesChannel = MethodChannel('com.walletpro/updates');
  final Dio _dio = Dio();
  final ApiClient _apiClient = ApiClient();

  /// Compares two semver strings (e.g. "1.7.0" and "1.6.0").
  /// Returns 1 if v1 > v2, -1 if v1 < v2, and 0 if equal.
  static int compareVersions(String v1, String v2) {
    final p1 = v1.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final p2 = v2.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final val1 = i < p1.length ? p1[i] : 0;
      final val2 = i < p2.length ? p2[i] : 0;
      if (val1 > val2) return 1;
      if (val1 < val2) return -1;
    }
    return 0;
  }

  /// Get runtime version name from Android package manager or fallback to constant
  Future<String> getInstalledVersion() async {
    try {
      final res = await _updatesChannel.invokeMapMethod<String, dynamic>('getAppVersion');
      final name = res?['versionName']?.toString();
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {}
    return AppVersion.version;
  }

  /// Check for latest release using GitHub directly, falling back to backend cache
  Future<UpdateInfo> checkForUpdate({String? currentVersion}) async {
    final installed = currentVersion ?? await getInstalledVersion();

    // 1. Try GitHub public releases API directly
    try {
      final res = await _dio.get(
        AppVersion.latestReleaseUrl,
        options: Options(
          headers: {'Accept': 'application/vnd.github.v3+json'},
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        return UpdateInfo.fromJson(res.data as Map<String, dynamic>, currentVersion: installed);
      }
    } catch (_) {}

    // 2. Fallback to backend route if GitHub direct request fails (e.g. rate limit)
    try {
      final backendData = await _apiClient.getLatestRelease();
      return UpdateInfo.fromJson(backendData, currentVersion: installed);
    } catch (e) {
      rethrow;
    }
  }

  /// Get the safe directory path on Android to store update APKs
  Future<String> getUpdateDirectory() async {
    try {
      final dir = await _updatesChannel.invokeMethod<String>('getUpdateDirectory');
      if (dir != null && dir.isNotEmpty) return dir;
    } catch (_) {}
    // Fallback path
    return '/sdcard/Android/data/com.walletpro.walletpro/files/updates';
  }

  /// Get the destination File object for a given update version
  Future<File> getExpectedApkFile(UpdateInfo info) async {
    final dirPath = await getUpdateDirectory();
    final fileName = 'walletpro-v${info.version}.apk';
    return File('$dirPath/$fileName');
  }

  /// Check if the APK has already been downloaded to disk
  Future<bool> isApkDownloaded(UpdateInfo info) async {
    try {
      final file = await getExpectedApkFile(info);
      if (!await file.exists()) return false;
      final len = await file.length();
      if (info.apkSize > 0) {
        return len == info.apkSize;
      }
      return len > 10 * 1024 * 1024; // > 10MB indicates a valid APK
    } catch (_) {
      return false;
    }
  }

  /// Download the APK with progress streaming
  Future<String> downloadApk(
    UpdateInfo info, {
    required void Function(double progress, int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final destFile = await getExpectedApkFile(info);
    final partFile = File('${destFile.path}.part');

    // Ensure parent directory exists
    if (!await destFile.parent.exists()) {
      await destFile.parent.create(recursive: true);
    }

    if (await partFile.exists()) {
      await partFile.delete();
    }

    await _dio.download(
      info.apkDownloadUrl,
      partFile.path,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        final progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
        onProgress(progress, received, total);
      },
    );

    // Atomically rename .part to final destination
    if (await destFile.exists()) {
      await destFile.delete();
    }
    await partFile.rename(destFile.path);

    return destFile.path;
  }

  /// Check if user has granted "Install unknown apps" permission on Android 8.0+
  Future<bool> canInstallUnknownApps() async {
    try {
      final res = await _updatesChannel.invokeMethod<bool>('canInstallUnknownApps');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Open Android settings screen for "Install unknown apps"
  Future<void> openInstallPermissionSettings() async {
    try {
      await _updatesChannel.invokeMethod('openInstallPermissionSettings');
    } catch (_) {}
  }

  /// Launch Android Package Installer for the downloaded APK
  Future<Map<String, dynamic>> installApk(String filePath) async {
    try {
      final res = await _updatesChannel.invokeMapMethod<String, dynamic>(
        'installApk',
        {'filePath': filePath},
      );
      return res ?? {'status': 'installing'};
    } catch (e) {
      throw Exception('Failed to launch installer: $e');
    }
  }

  /// Trigger native Android update notification in the notification bar
  Future<void> showUpdateNotification(UpdateInfo info) async {
    try {
      await _updatesChannel.invokeMethod('showUpdateNotification', {
        'version': info.tagName,
        'notes': info.changelog,
      });
    } catch (_) {}
  }
}
