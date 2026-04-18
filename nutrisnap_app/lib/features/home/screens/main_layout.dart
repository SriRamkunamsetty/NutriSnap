import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/unsaved_changes_provider.dart';
import '../../../core/providers/connectivity_provider.dart';

class MainLayout extends ConsumerWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  void _onItemTapped(BuildContext context, WidgetRef ref, int index) async {
    final currentIndex = _calculateSelectedIndex(context);
    if (currentIndex == index) return;

    final hasUnsavedChanges = ref.read(unsavedChangesProvider);
    if (hasUnsavedChanges) {
      final shouldNavigate = await _showUnsavedChangesDialog(context);
      if (shouldNavigate != true) return;
      
      // Reset unsaved changes flag if they choose to discard
      ref.read(unsavedChangesProvider.notifier).state = false;
    }

    if (!context.mounted) return;

    if (index == 0) {
      context.go(AppRoutes.home);
    } else if (index == 1) {
      context.go(AppRoutes.history);
    } else if (index == 2) {
      context.go(AppRoutes.analytics);
    } else if (index == 3) {
      context.go(AppRoutes.settings);
    }
  }

  Future<bool?> _showUnsavedChangesDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: Colors.orange.shade500),
              const SizedBox(width: 12),
              const Text('Unsaved Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: const Text(
            'You have unsaved changes. If you leave now, your edits will be discarded. Are you sure you want to navigate away?',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade500,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Discard Edits', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(AppRoutes.history)) {
      return 1;
    }
    if (location.startsWith(AppRoutes.analytics)) {
      return 2;
    }
    if (location.startsWith(AppRoutes.settings)) {
      return 3;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final userState = ref.watch(userNotifierProvider);
    final authUser = userState.authUser;
    final isUnverified = authUser != null && !authUser.emailVerified && authUser.providerData.any((p) => p.providerId == 'password');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          if (!isOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.red.shade600,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.wifiOff, color: Colors.white, size: 14),
                  SizedBox(width: 8),
                  Text(
                    'Offline Mode: Data will sync when reconnected',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          if (isUnverified)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              color: Colors.amber.shade50,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.amber.shade200)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle, color: Colors.amber.shade800, size: 16),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Please verify your email address to secure your account.',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                       try {
                         await ref.read(userNotifierProvider.notifier).sendEmailVerification();
                         if (context.mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('Verification email sent! Please check your inbox.')),
                           );
                         }
                       } catch (e) {
                         if (context.mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(content: Text('Error: $e')),
                           );
                         }
                       }
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Resend',
                      style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: AppColors.border, width: 1.0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            )
          ]
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: BottomNavigationBar(
              currentIndex: _calculateSelectedIndex(context),
              onTap: (index) => _onItemTapped(context, ref, index),
              backgroundColor: Colors.white,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Colors.green.shade600,
              unselectedItemColor: AppColors.textTertiary,
              selectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              unselectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              items: const [
                BottomNavigationBarItem(
                  icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(LucideIcons.home)),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(LucideIcons.clock)),
                  label: 'History',
                ),
                BottomNavigationBarItem(
                  icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(LucideIcons.activity)),
                  label: 'Analytics',
                ),
                BottomNavigationBarItem(
                  icon: Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(LucideIcons.settings)),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
