import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/vault_providers.dart';
import '../screens/home_screen.dart';
import '../screens/lock_screen.dart';
import '../screens/setup_screen.dart';
import '../screens/splash_screen.dart';

abstract final class Routes {
  static const splash = '/';
  static const setup = '/setup';
  static const lock = '/lock';
  static const home = '/home';
}

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 380),
  transitionsBuilder: (context, animation, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
    child: child,
  ),
);

/// Routes follow the vault's state: needs setup → /setup, locked → /lock,
/// unlocked → /home. Any other location redirects, so the vault can't be
/// reached without unlocking.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(vaultControllerProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(vaultControllerProvider);
      final here = state.matchedLocation;
      final target = switch (status) {
        AsyncData(:final value) => switch (value) {
          VaultStatus.needsSetup => Routes.setup,
          VaultStatus.locked => Routes.lock,
          VaultStatus.unlocked => Routes.home,
        },
        _ => Routes.splash,
      };
      return here == target ? null : target;
    },
    routes: [
      GoRoute(path: Routes.splash, pageBuilder: (_, s) => _fade(s, const SplashScreen())),
      GoRoute(path: Routes.setup, pageBuilder: (_, s) => _fade(s, const SetupScreen())),
      GoRoute(path: Routes.lock, pageBuilder: (_, s) => _fade(s, const LockScreen())),
      GoRoute(path: Routes.home, pageBuilder: (_, s) => _fade(s, const HomeScreen())),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
