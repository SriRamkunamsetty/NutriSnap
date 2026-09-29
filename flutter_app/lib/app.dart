import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/app_providers.dart';
import 'core/router/app_router.dart';
import 'core/services/reminder_service.dart';
import 'core/services/retention_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/user_provider.dart';

/// Set when the start-up retention pass removed old records, so Home can tell
/// the user once. `null` once dismissed.
final retentionNoticeProvider = StateProvider<RetentionReport?>((ref) => null);

class NutriSnapApp extends ConsumerStatefulWidget {
  const NutriSnapApp({super.key});

  @override
  ConsumerState<NutriSnapApp> createState() => _NutriSnapAppState();
}

class _NutriSnapAppState extends ConsumerState<NutriSnapApp> {
  bool _startupDone = false;

  @override
  void initState() {
    super.initState();
    // Run background housekeeping as soon as the profile is ready, never
    // blocking the first frame.
    ref.listenManual(userNotifierProvider, (_, next) {
      if (!_startupDone && !next.isLoading && next.hasCompletedOnboarding) {
        _startupDone = true;
        _runStartupTasks();
      }
    }, fireImmediately: true);
  }

  Future<void> _runStartupTasks() async {
    final report = await ref.read(retentionServiceProvider).run();
    if (mounted && (report.removedAnything || report.failed)) {
      ref.read(retentionNoticeProvider.notifier).state = report;
    }
    await ref.read(reminderServiceProvider).syncSchedule();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'NutriSnap AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}
