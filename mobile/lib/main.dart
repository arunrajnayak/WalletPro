import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/datasources/local/local_cache.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalCache.init();
  // await Firebase.initializeApp();
  runApp(
    const ProviderScope(
      child: WalletProApp(),
    ),
  );
}
