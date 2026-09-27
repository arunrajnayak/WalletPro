class ApiConstants {
  // Production Vercel URL for personal use:
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://backend-beta-six-82.vercel.app',
  );

  static const String walletApiBaseUrl = 'https://rest.budgetbakers.com/wallet';
}
