import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/user_provider.dart';
import '../../features/auth/screens/auth_screen.dart'; 
import '../../features/auth/screens/splash_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/home/screens/result_screen.dart';
import '../../features/home/screens/analytics_screen.dart';
import '../../features/home/screens/history_screen.dart';
import '../../features/home/screens/main_layout.dart';
import '../../features/chat/screens/ai_chat_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../constants/app_routes.dart';
import '../models/scan_result.dart';

CustomTransitionPage<void> _buildNativePageTransition({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.04, 0.0),
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

// ==========================================
// ROUTER CONFIGURATION
// ==========================================

// 2. Optimize Router Rebuilds: RouterNotifier prevents GoRouter from rebuilding its core layer,
// only triggering the 'redirect' evaluation block safely when necessary tracked properties shift.
class RouterNotifier extends ChangeNotifier {
  final Ref _ref;
  RouterNotifier(this._ref) {
    _ref.listen(userNotifierProvider.select((s) => s.isLoading), (_, __) => notifyListeners());
    _ref.listen(userNotifierProvider.select((s) => s.authUser?.uid), (_, __) => notifyListeners());
    _ref.listen(userNotifierProvider.select((s) => s.profile?.hasCompletedOnboarding), (_, __) => notifyListeners());
  }
}

final routerNotifierProvider = Provider((ref) => RouterNotifier(ref));

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: notifier,
    // 5. Add Error Route Handling
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Oops! Page not found.'),
            TextButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Return Home'),
            ),
          ],
        ),
      ),
    ),
    redirect: (context, state) {
      // Pull state values reactively without causing GoRouter to reconstruct
      final userState = ref.read(userNotifierProvider);
      final isLoading = userState.isLoading;
      final isAuth = userState.authUser != null;
      final hasCompletedOnboarding = userState.profile?.hasCompletedOnboarding ?? false;
      
      final currentLoc = state.matchedLocation;
      final isSplash = currentLoc == AppRoutes.splash;
      final isLoggingIn = currentLoc == AppRoutes.auth;
      final isOnboarding = currentLoc == AppRoutes.onboarding;

      // 4. Initial Screen Loading Flow
      if (isLoading) {
        return isSplash ? null : AppRoutes.splash; // 1. Prevent Redirect Loops (Checks current locale first)
      }

      // Auth validation gate
      if (!isAuth) {
        return isLoggingIn ? null : AppRoutes.auth;
      }

      // Onboarding validation gate
      if (!hasCompletedOnboarding) {
        return isOnboarding ? null : AppRoutes.onboarding;
      }

      // Prevent authenticated, fully onboarded users from getting trapped on splash/auth nodes
      if (isSplash || isLoggingIn || isOnboarding) {
        return AppRoutes.home;
      }

      // 3. Support Deep Links - Returns null allowing any valid auth path (/result/:id etc) to load cleanly
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainLayout(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (context, state) => _buildNativePageTransition(
              context: context,
              state: state,
              child: const HomeScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.history,
            pageBuilder: (context, state) => _buildNativePageTransition(
              context: context,
              state: state,
              child: const HistoryScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.analytics,
            pageBuilder: (context, state) => _buildNativePageTransition(
              context: context,
              state: state,
              child: const AnalyticsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.chat,
            pageBuilder: (context, state) => _buildNativePageTransition(
              context: context,
              state: state,
              child: const AIChatScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (context, state) => _buildNativePageTransition(
              context: context,
              state: state,
              child: const SettingsScreen(),
            ),
          ),
          GoRoute(
            path: '${AppRoutes.result}/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              final scan = state.extra as ScanResult?;
              return _buildNativePageTransition(
                context: context,
                state: state,
                child: ResultScreen(id: id, initialScan: scan),
              );
            },
          ),
        ],
      ),
    ],
  );
});
