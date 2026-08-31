import 'package:flutter/material.dart';

import 'views/auth/login_page.dart';
import 'views/splash/splash_screen.dart';
import 'services/server_reconnect.dart';

void main() => runApp(const RestaurantApp());

class RestaurantApp extends StatefulWidget {
  const RestaurantApp({
    super.key,
    this.initialChecks = runInitialChecks,
    this.skipPairing = false,
    this.reconnectCheck = reconnectToPairedServer,
  });

  final Future<void> Function() initialChecks;
  final bool skipPairing;
  final Future<bool> Function() reconnectCheck;

  @override
  State<RestaurantApp> createState() => _RestaurantAppState();
}

class _RestaurantAppState extends State<RestaurantApp>
    with WidgetsBindingObserver {
  Locale _locale = WidgetsBinding.instance.platformDispatcher.locale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    setState(() => _locale = locales?.first ?? const Locale('en'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Restaurant Login',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF9F9F8),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8798AC)),
        fontFamily: 'sans-serif',
      ),
      home: SplashScreen(
        strings: AppStrings.fromLocale(_locale),
        initialChecks: widget.initialChecks,
        skipPairing: widget.skipPairing,
        reconnectCheck: widget.reconnectCheck,
      ),
    );
  }
}
