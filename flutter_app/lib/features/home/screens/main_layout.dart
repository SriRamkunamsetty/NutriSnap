import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/unsaved_changes_provider.dart';

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

    const paths = [
      AppRoutes.home,
      AppRoutes.history,
      AppRoutes.activity,
      AppRoutes.coach,
      AppRoutes.settings,
    ];
    context.go(paths[index]);
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
    if (location.startsWith(AppRoutes.history)) return 1;
    if (location.startsWith(AppRoutes.activity)) return 2;
    if (location.startsWith(AppRoutes.coach) ||
        location.startsWith(AppRoutes.chat) ||
        location.startsWith(AppRoutes.analytics)) {
      return 3;
    }
    if (location.startsWith(AppRoutes.settings)) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: _IosTabBar(
        currentIndex: _calculateSelectedIndex(context),
        onTap: (i) => _onItemTapped(context, ref, i),
      ),
    );
  }
}

/// Frosted, Apple-style tab bar with generous 48-pt targets and labels that
/// never rely on colour alone.
class _IosTabBar extends StatelessWidget {
  const _IosTabBar({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (LucideIcons.house, 'Home'),
    (LucideIcons.clock, 'History'),
    (LucideIcons.footprints, 'Activity'),
    (LucideIcons.sparkles, 'Coach'),
    (LucideIcons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            border: const Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == currentIndex,
                        label: _items[i].$2,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onTap(i);
                          },
                          child: ExcludeSemantics(
                            child: SizedBox(
                              height: 52,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: i == currentIndex ? Colors.green.shade50 : Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      _items[i].$1,
                                      size: 21,
                                      color: i == currentIndex ? Colors.green.shade700 : AppColors.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _items[i].$2,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: i == currentIndex ? FontWeight.w800 : FontWeight.w600,
                                      color: i == currentIndex ? Colors.green.shade700 : AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
