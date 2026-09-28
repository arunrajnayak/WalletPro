import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_version.dart';
import '../../data/datasources/local/update_service.dart';

class AppUpdateState {
  final UpdateInfo? updateInfo;
  final bool isChecking;
  final bool isDownloading;
  final double downloadProgress;
  final int receivedBytes;
  final int totalBytes;
  final bool isDownloaded;
  final String? downloadedApkPath;
  final String? errorMessage;
  final DateTime? lastChecked;
  final bool autoCheckEnabled;
  final String currentVersion;
  final bool isBannerDismissed;

  AppUpdateState({
    this.updateInfo,
    this.isChecking = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.isDownloaded = false,
    this.downloadedApkPath,
    this.errorMessage,
    this.lastChecked,
    this.autoCheckEnabled = true,
    this.currentVersion = AppVersion.version,
    this.isBannerDismissed = false,
  });

  AppUpdateState copyWith({
    UpdateInfo? updateInfo,
    bool? isChecking,
    bool? isDownloading,
    double? downloadProgress,
    int? receivedBytes,
    int? totalBytes,
    bool? isDownloaded,
    String? downloadedApkPath,
    String? errorMessage,
    DateTime? lastChecked,
    bool? autoCheckEnabled,
    String? currentVersion,
    bool? isBannerDismissed,
  }) {
    return AppUpdateState(
      updateInfo: updateInfo ?? this.updateInfo,
      isChecking: isChecking ?? this.isChecking,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      downloadedApkPath: downloadedApkPath ?? this.downloadedApkPath,
      errorMessage: errorMessage,
      lastChecked: lastChecked ?? this.lastChecked,
      autoCheckEnabled: autoCheckEnabled ?? this.autoCheckEnabled,
      currentVersion: currentVersion ?? this.currentVersion,
      isBannerDismissed: isBannerDismissed ?? this.isBannerDismissed,
    );
  }
}

class AppUpdateNotifier extends StateNotifier<AppUpdateState> {
  final UpdateService _updateService = UpdateService();
  CancelToken? _cancelToken;

  AppUpdateNotifier() : super(AppUpdateState()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('pref_auto_check_updates') ?? true;
      final runtimeVer = await _updateService.getInstalledVersion();
      state = state.copyWith(autoCheckEnabled: enabled, currentVersion: runtimeVer);
    } catch (_) {}
  }

  /// Check for new updates with optional notification delivery
  Future<void> checkForUpdate({
    bool userInitiated = false,
    bool notifyIfAvailable = true,
  }) async {
    if (state.isChecking || state.isDownloading) return;

    state = state.copyWith(isChecking: true, errorMessage: null);

    try {
      final runtimeVer = await _updateService.getInstalledVersion();
      final info = await _updateService.checkForUpdate(currentVersion: runtimeVer);
      final alreadyDownloaded = await _updateService.isApkDownloaded(info);
      String? downloadedPath;
      if (alreadyDownloaded) {
        final file = await _updateService.getExpectedApkFile(info);
        downloadedPath = file.path;
      }

      state = state.copyWith(
        updateInfo: info,
        isChecking: false,
        isDownloaded: alreadyDownloaded,
        downloadedApkPath: downloadedPath,
        lastChecked: DateTime.now(),
        currentVersion: runtimeVer,
      );

      // Trigger notification if update is available and not already notified
      if (info.isUpdateAvailable && notifyIfAvailable && state.autoCheckEnabled && !userInitiated) {
        final prefs = await SharedPreferences.getInstance();
        final lastNotifiedTag = prefs.getString('last_notified_update_tag');
        if (lastNotifiedTag != info.tagName) {
          await _updateService.showUpdateNotification(info);
          await prefs.setString('last_notified_update_tag', info.tagName);
        }
      }
    } catch (e) {
      state = state.copyWith(
        isChecking: false,
        errorMessage: userInitiated ? 'Failed to check for updates: $e' : null,
        lastChecked: DateTime.now(),
      );
    }
  }

  /// Download APK with real-time progress tracking
  Future<void> downloadAndInstall() async {
    final info = state.updateInfo;
    if (info == null || !info.isUpdateAvailable) return;

    // Check if already downloaded
    if (state.isDownloaded && state.downloadedApkPath != null) {
      await installUpdate();
      return;
    }

    _cancelToken = CancelToken();
    state = state.copyWith(
      isDownloading: true,
      downloadProgress: 0.0,
      receivedBytes: 0,
      totalBytes: info.apkSize,
      errorMessage: null,
    );

    try {
      final savedPath = await _updateService.downloadApk(
        info,
        cancelToken: _cancelToken,
        onProgress: (progress, received, total) {
          state = state.copyWith(
            downloadProgress: progress,
            receivedBytes: received,
            totalBytes: total > 0 ? total : info.apkSize,
          );
        },
      );

      state = state.copyWith(
        isDownloading: false,
        isDownloaded: true,
        downloadedApkPath: savedPath,
        downloadProgress: 1.0,
      );

      // Immediately launch installer
      await installUpdate();
    } catch (e) {
      if (_cancelToken?.isCancelled ?? false) {
        state = state.copyWith(isDownloading: false, downloadProgress: 0.0);
      } else {
        state = state.copyWith(
          isDownloading: false,
          errorMessage: 'Download failed: $e',
        );
      }
    }
  }

  /// Cancel active download
  void cancelDownload() {
    _cancelToken?.cancel('User cancelled download');
    state = state.copyWith(isDownloading: false, downloadProgress: 0.0);
  }

  /// Launch Android Package Installer for the downloaded APK
  Future<Map<String, dynamic>> installUpdate() async {
    final path = state.downloadedApkPath;
    if (path == null) {
      state = state.copyWith(errorMessage: 'APK file not found. Please download again.');
      return {'status': 'error'};
    }

    try {
      final result = await _updateService.installApk(path);
      return result;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Installation launch failed: $e');
      return {'status': 'error'};
    }
  }

  /// Check permission for unknown app sources
  Future<bool> canInstallUnknownApps() async {
    return _updateService.canInstallUnknownApps();
  }

  /// Open Android settings for unknown app sources
  Future<void> openInstallPermissionSettings() async {
    await _updateService.openInstallPermissionSettings();
  }

  /// Toggle auto-check updates preference
  Future<void> setAutoCheckEnabled(bool enabled) async {
    state = state.copyWith(autoCheckEnabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_auto_check_updates', enabled);
    } catch (_) {}
  }

  /// Dismiss dashboard banner for the current session
  void dismissBanner() {
    state = state.copyWith(isBannerDismissed: true);
  }
}

final appUpdateProvider = StateNotifierProvider<AppUpdateNotifier, AppUpdateState>((ref) {
  return AppUpdateNotifier();
});
