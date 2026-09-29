import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/user_provider.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/home/screens/result_screen.dart';
import '../../features/home/screens/history_screen.dart';
import '../../features/home/screens/main_layout.dart';
import '../../features/scan/screens/scan_review_screen.dart';
import '../../features/activity/screens/activity_screen.dart';
import '../../features/food/screens/food_library_screen.dart';
import '../../features/food/screens/food_twin_screen.dart';
import '../../features/messos/screens/messos_screen.dart';
import '../../features/coach/screens/coach_hub_screen.dart';
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
      final userState = ref.read(userNotifierProvider);
      final loc = state.matchedLocation;
      final isSplash = loc == AppRoutes.splash;
      final isOnboarding = loc == AppRoutes.onboarding;

      if (userState.isLoading || userState.errorMessage != null) {
        return isSplash ? null : AppRoutes.splash;
      }
      if (!userState.hasCompletedOnboarding) {
        return isOnboarding ? null : AppRoutes.onboarding;
      }
      // Finished onboarding: never park on splash / onboarding again.
      if (isSplash || isOnboarding) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.foodLibrary,
        pageBuilder: (context, state) =>
            _buildNativePageTransition(context: context, state: state, child: const FoodLibraryScreen()),
      ),
      GoRoute(
        path: AppRoutes.foodTwin,
        pageBuilder: (context, state) =>
            _buildNativePageTransition(context: context, state: state, child: const FoodTwinScreen()),
      ),
      GoRoute(
        path: AppRoutes.messOs,
        pageBuilder: (context, state) =>
            _buildNativePageTransition(context: context, state: state, child: const MessOsScreen()),
      ),
      // Full-screen review of a scanned meal (outside the tab bar).
      GoRoute(
        path: AppRoutes.scanReview,
        redirect: (context, state) =>
            state.extra is ScanReviewArgs ? null : AppRoutes.home,
        pageBuilder: (context, state) => _buildNativePageTransition(
          context: context,
          state: state,
          child: ScanReviewScreen(args: state.extra as ScanReviewArgs),
        ),
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
            path: AppRoutes.activity,
            pageBuilder: (context, state) => _buildNativePageTransition(
              context: context,
              state: state,
              child: const ActivityScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.coach,
            pageBuilder: (context, state) => _buildNativePageTransition(
              context: context,
              state: state,
              child: CoachHubScreen(
                initialTab: state.uri.queryParameters['tab'] == 'insights'
                    ? CoachTab.insights
                    : CoachTab.coach,
              ),
            ),
          ),
          // Older links keep working and land on the matching Coach tab.
          GoRoute(
            path: AppRoutes.analytics,
            redirect: (context, state) => '${AppRoutes.coach}?tab=insights',
          ),
          GoRoute(
            path: AppRoutes.chat,
            redirect: (context, state) => AppRoutes.coach,
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
