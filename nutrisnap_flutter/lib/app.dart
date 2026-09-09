import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class NutriSnapApp extends ConsumerWidget {
  const NutriSnapApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. GoRouter Injection
    final router = ref.watch(goRouterProvider);

    // 2. Theme Initialization
    return MaterialApp.router(
      title: 'NutriSnap AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
      routerDelegate: router.routerDelegate,
    );
  }
}
