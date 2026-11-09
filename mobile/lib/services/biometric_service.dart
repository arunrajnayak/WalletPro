import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Service wrapping `local_auth` for biometric / device-credential
/// authentication. Requires MainActivity to extend FlutterFragmentActivity.
class BiometricService {
  static final _auth = LocalAuthentication();

  /// Returns `true` when the device can authenticate — either via biometrics
  /// (fingerprint, face, iris) OR via device credentials (PIN, pattern,
  /// password). Uses both `canCheckBiometrics` and `isDeviceSupported()` so
  /// that PIN-only devices are not incorrectly excluded.
  static Future<bool> isAvailable() async {
    try {
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheckBiometrics || isDeviceSupported;
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] isAvailable error: ${e.code} – ${e.message}');
      return false;
    }
  }

  /// Prompts the user to authenticate.
  ///
  /// `biometricOnly: false` allows fallback to the device PIN / pattern.
  /// `stickyAuth: true` keeps the prompt alive if the app is briefly
  /// backgrounded (e.g. by a system overlay).
  /// Returns `true` on successful authentication, `false` otherwise.
  static Future<bool> authenticate({
    String reason = 'Authenticate to access WalletPro',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('[BiometricService] authenticate error: ${e.code} – ${e.message}');
      return false;
    }
  }
}
