class ApiConstants {
  // Production Vercel URL for personal use:
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://walletpro-arunraj.vercel.app',
  );

  static const String walletApiBaseUrl = 'https://rest.budgetbakers.com/wallet';
}
