import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Singleton-style service wrapping `local_auth` for biometric / device-PIN
/// authentication checks throughout the app.
class BiometricService {
  static final _auth = LocalAuthentication();

  /// Returns `true` when the device supports biometrics AND at least one
  /// biometric credential (fingerprint, face, etc.) is enrolled.
  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  /// Prompts the user to authenticate.
  ///
  /// [reason] is the human-readable string shown in the system dialog.
  /// `biometricOnly: false` allows fallback to the device PIN / pattern.
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
    } on PlatformException {
      return false;
    }
  }
}
