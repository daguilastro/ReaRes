import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/client_identity.dart';
import '../../models/client_user.dart';
import '../auth/login_page.dart';
import '../pairing/pairing_page.dart';
import '../../services/server_reconnect.dart';
import '../../services/client_auth_api.dart';
import '../rooms/rooms_page.dart';

/// Punto único para las comprobaciones que deben terminar antes del login.
/// Las verificaciones reales pueden añadirse a esta función sin cambiar la UI.
Future<void> runInitialChecks() async {
  await Future.wait([
    ensureClientIdentity(),
    // Mantiene visible la animación el tiempo suficiente para evitar un destello.
    Future<void>.delayed(const Duration(milliseconds: 1400)),
  ]);
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.strings,
    this.initialChecks = runInitialChecks,
    this.skipPairing = false,
    this.reconnectCheck = reconnectToPairedServer,
    this.reconnectTimeout = const Duration(seconds: 8),
    this.restoreSession = restoreClientSession,
  });

  final AppStrings strings;
  final Future<void> Function() initialChecks;
  final bool skipPairing;
  final Future<bool> Function() reconnectCheck;
  final Duration reconnectTimeout;
  final Future<ClientSession?> Function() restoreSession;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;
  _StartupView _view = _StartupView.splash;
  ClientSession? _authenticatedSession;
  bool _loginIsFading = false;
  final _roomsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: .78, end: 1.16).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );
    _initialize();
  }

  Future<void> _initialize() async {
    var reconnected = false;
    try {
      await widget.initialChecks();
      if (!mounted) return;
      reconnected =
          widget.skipPairing ||
          await widget.reconnectCheck().timeout(
            widget.reconnectTimeout,
            onTimeout: () {
              debugPrint(
                'La reconexión mDNS excedió ${widget.reconnectTimeout.inSeconds}s.',
              );
              return false;
            },
          );
    } on Object catch (error, stackTrace) {
      // Una comprobación fallida nunca debe dejar el splash bloqueado. La
      // pantalla de pairing podrá volver a crear/verificar la identidad.
      debugPrint('Las comprobaciones iniciales fallaron: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) return;
    _pulseController.stop();
    if (reconnected) {
      try {
        _authenticatedSession = await widget.restoreSession().timeout(
          const Duration(seconds: 1),
          onTimeout: () => null,
        );
      } on Object catch (error) {
        debugPrint('No se pudo restaurar la sesión: $error');
        _authenticatedSession = null;
      }
      if (!mounted) return;
    }
    setState(
      () => _view = !reconnected
          ? _StartupView.pairing
          : _authenticatedSession == null
          ? _StartupView.login
          : _StartupView.rooms,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 560),
      reverseDuration: const Duration(milliseconds: 560),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      // La pantalla nueva permanece completamente visible debajo mientras la
      // anterior se desvanece. Así nunca aparece el fondo negro del compositor.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [?currentChild, ...previousChildren],
      ),
      transitionBuilder: (child, animation) =>
          _FadeOutTransition(animation: animation, child: child),
      child: _view == _StartupView.rooms
          ? RoomsPage(
              key: _roomsKey,
              session: _authenticatedSession!,
              spanish: widget.strings.isSpanish,
            )
          : _view == _StartupView.login
          ? Stack(
              key: const ValueKey('login-stage'),
              fit: StackFit.expand,
              children: [
                if (_authenticatedSession != null)
                  RoomsPage(
                    key: _roomsKey,
                    session: _authenticatedSession!,
                    spanish: widget.strings.isSpanish,
                  ),
                AnimatedOpacity(
                  opacity: _loginIsFading ? 0 : 1,
                  duration: const Duration(milliseconds: 560),
                  curve: Curves.easeInOut,
                  onEnd: () {
                    if (_loginIsFading && mounted) {
                      setState(() => _view = _StartupView.rooms);
                    }
                  },
                  child: IgnorePointer(
                    ignoring: _loginIsFading,
                    child: LoginPage(
                      key: const ValueKey('login-screen'),
                      strings: widget.strings,
                      onAuthenticated: (session) => setState(() {
                        _authenticatedSession = session;
                        _loginIsFading = true;
                      }),
                    ),
                  ),
                ),
              ],
            )
          : _view == _StartupView.pairing
          ? PairingPage(
              key: const ValueKey('pairing-screen'),
              spanish: widget.strings.isSpanish,
              onPaired: () => setState(() => _view = _StartupView.login),
            )
          : Scaffold(
              key: const ValueKey('splash-screen'),
              body: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) => Transform.scale(
                    scale: _pulse.value,
                    child: Opacity(
                      opacity: .68 + (((_pulse.value - .78) / .38) * .32),
                      child: child,
                    ),
                  ),
                  child: SizedBox.square(
                    dimension: 150,
                    child: SvgPicture.asset(
                      'assets/logo.svg',
                      key: const ValueKey('splash-logo'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

enum _StartupView { splash, pairing, login, rooms }

class _FadeOutTransition extends StatelessWidget {
  const _FadeOutTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        if (animation.status != AnimationStatus.reverse) return child!;
        return Opacity(opacity: animation.value, child: child);
      },
    );
  }
}
