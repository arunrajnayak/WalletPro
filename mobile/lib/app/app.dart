import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/datasources/local/notification_service.dart';
import '../data/datasources/local/sms_service.dart';
import '../data/datasources/remote/api_client.dart';
import '../presentation/providers/pending_count_provider.dart';
import '../presentation/providers/suggestions_provider.dart';
import '../presentation/providers/theme_provider.dart';
import 'router.dart';
import 'theme.dart';

class WalletProApp extends ConsumerStatefulWidget {
  const WalletProApp({super.key});

  @override
  ConsumerState<WalletProApp> createState() => _WalletProAppState();
}

class _WalletProAppState extends ConsumerState<WalletProApp> with WidgetsBindingObserver {
  final ApiClient _api = ApiClient();
  final SmsReaderService _smsReader = SmsReaderService();
  bool _isAutoScanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize notification service and listen for real-time transaction detection
    NotificationService.init(onTransactionDetected: () {
      _triggerAutoScan();
    });

    // Check if app was launched via notification click
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialRoute = await NotificationService.getInitialRoute();
      if (initialRoute != null && initialRoute.isNotEmpty && mounted) {
        ref.read(routerProvider).go(initialRoute);
      }
      _triggerAutoScan();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerAutoScan();
    }
  }

  /// Automatically scan inbox in the background without user interaction
  Future<void> _triggerAutoScan() async {
    if (_isAutoScanning) return;
    _isAutoScanning = true;

    try {
      final hasPerm = await _smsReader.hasPermission();
      if (hasPerm) {
        final result = await _smsReader.scanAndSyncInbox(apiClient: _api);
        // Refresh pending count
        final stats = await _api.getSuggestionStats();
        final int pending = (stats['pending'] as num?)?.toInt() ?? 0;
        if (mounted) {
          ref.read(pendingCountProvider.notifier).state = pending;
          if (result['created'] != null && result['created']! > 0) {
            final freshSuggestions = await _api.getSuggestions(status: 'pending', limit: 100);
            if (mounted) {
              ref.read(pendingSuggestionsProvider.notifier).setSuggestions(freshSuggestions);
            }
          }
        }
        await NotificationService.updatePendingCount(pending);
      }
    } catch (_) {
      // Ignore background auto-scan errors
    } finally {
      _isAutoScanning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'WalletPro',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
