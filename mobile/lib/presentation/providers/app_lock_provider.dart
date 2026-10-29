import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/local/local_cache.dart';
import '../../services/biometric_service.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class AppLockState {
  final bool isEnabled;
  final bool isUnlocked;

  const AppLockState({
    required this.isEnabled,
    required this.isUnlocked,
  });

  AppLockState copyWith({bool? isEnabled, bool? isUnlocked}) => AppLockState(
        isEnabled: isEnabled ?? this.isEnabled,
        isUnlocked: isUnlocked ?? this.isUnlocked,
      );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class AppLockNotifier extends StateNotifier<AppLockState> {
  AppLockNotifier()
      : super(const AppLockState(isEnabled: false, isUnlocked: true));

  static const _kAppLockKey = 'app_lock_enabled';

  /// Reads the persisted setting and updates state accordingly.
  /// Call this once during app startup (e.g. in `addPostFrameCallback`).
  Future<void> loadSettings() async {
    final raw = await LocalCache.getStringAsync(_kAppLockKey);
    final enabled = raw == 'true';
    state = AppLockState(
      isEnabled: enabled,
      // Start locked when the feature is enabled so the user must authenticate
      // on every cold-start.
      isUnlocked: !enabled,
    );
  }

  /// Enables App Lock and persists the setting.
  Future<void> enable() async {
    await LocalCache.setString(_kAppLockKey, 'true');
    state = state.copyWith(isEnabled: true, isUnlocked: false);
  }

  /// Disables App Lock and persists the setting.
  Future<void> disable() async {
    await LocalCache.setString(_kAppLockKey, 'false');
    state = state.copyWith(isEnabled: false, isUnlocked: true);
  }

  /// Locks the app (called when the app is paused / backgrounded).
  void lock() {
    if (state.isEnabled) {
      state = state.copyWith(isUnlocked: false);
    }
  }

  /// Triggers biometric / device-PIN authentication and unlocks on success.
  /// Returns `true` if authentication succeeded.
  Future<bool> authenticate() async {
    final success = await BiometricService.authenticate();
    if (success) {
      state = state.copyWith(isUnlocked: true);
    }
    return success;
  }

  /// Convenience getter: `true` when the app is either unlocked or lock is
  /// disabled entirely.
  bool get isAuthenticated => !state.isEnabled || state.isUnlocked;
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final appLockProvider =
    StateNotifierProvider<AppLockNotifier, AppLockState>((ref) {
  return AppLockNotifier();
});
