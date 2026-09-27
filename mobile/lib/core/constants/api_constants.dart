class ApiConstants {
  // Default backend URL (can be your Vercel deployment URL e.g. https://your-walletpro.vercel.app)
  // For local testing on Android emulator use: http://10.0.2.2:3000
  // For iOS simulator use: http://localhost:3000
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String walletApiBaseUrl = 'https://rest.budgetbakers.com/wallet';
}
