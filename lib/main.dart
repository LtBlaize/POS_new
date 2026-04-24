import 'dart:io'; // ← ADD
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/foundation.dart';
import 'config/app_router.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/local_db_service.dart';
import 'core/services/sync_queue_service.dart';
import 'core/services/lan_server_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop only — Android/iOS use native sqflite, no FFI needed
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await Supabase.initialize(
    url: 'https://qsdbufdixhyqlbygrncp.supabase.co',
    anonKey: 'sb_publishable_IMKcLGls9al71UvjElf_Kw_iC0N4Dqu',
  );

  final container = ProviderContainer();

  await container.read(localDbServiceProvider).db;
  await container.read(connectivityServiceProvider).init();
  container.read(syncQueueServiceProvider).init();

  // LAN server only makes sense on desktop (cashier device)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await container.read(lanServerServiceProvider).start();
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // ← ADD: listen for sync complete and show toast
    ref.listen<DateTime?>(syncCompleteProvider, (prev, next) {
      if (next == null) return;
      final ctx = router.navigatorKey.currentContext;
      if (ctx == null) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.cloud_done_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('All changes synced to server'),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });

    return MaterialApp(
      title: 'POS System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F3460)),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      initialRoute: '/login',
      onGenerateRoute: router.onGenerateRoute,
    );
  }
}