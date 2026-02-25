import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/services/payment_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Stripe must be initialised before runApp so that the PaymentService
  // provider is ready as soon as the widget tree mounts.
  PaymentService.initialize();

  await _initFirebase();

  runApp(
    const ProviderScope(
      child: DrezzyApp(),
    ),
  );
}

/// Initialises Firebase. Swallows [UnsupportedError] thrown by the stub
/// [DefaultFirebaseOptions] so the app can still launch during development
/// before `flutterfire configure` has been run.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('[Firebase] Initialised successfully.');
  } on UnsupportedError catch (e) {
    debugPrint(
      '[Firebase] Skipped initialisation (stub config):\n$e\n'
      'To connect to a real Firebase project, run:\n'
      '  flutterfire configure --project=<your-firebase-project-id>',
    );
  } catch (e, st) {
    debugPrint('[Firebase] Unexpected initialisation error:\n$e\n$st');
  }
}

class DrezzyApp extends ConsumerWidget {
  const DrezzyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Drezzy',
      debugShowCheckedModeBanner: false,
      theme: DrezzyTheme.light,
      darkTheme: DrezzyTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
