import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/models/reminder.dart';
import '../../../core/services/reminder_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ui_feedback.dart';

class MealRemindersCard extends ConsumerWidget {
  const MealRemindersCard({super.key});

  void _openReminderSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const MealRemindersSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(mealRemindersProvider);
    final activeCount = reminders.where((r) => r.enabled).length;

    return InkWell(
      onTap: () => _openReminderSheet(context),
      borderRadius: BorderRadius.circular(32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(LucideIcons.bellRing, color: Colors.amber.shade700, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Meal Reminders',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          '$activeCount OF 3 DAILY NOTIFICATIONS ACTIVE',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textTertiary,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: activeCount > 0 ? Colors.green.shade50 : AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    activeCount > 0 ? 'Active' : 'Muted',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: activeCount > 0 ? Colors.green.shade700 : AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Horizontal Pill Displays for Breakfast, Lunch, Dinner
            Row(
              children: reminders.map((r) {
                final isBreakfast = r.type == 'breakfast';
                final isLunch = r.type == 'lunch';
                final icon = isBreakfast
                    ? '🥐'
                    : (isLunch ? '🥗' : '🍲');

                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: r.enabled ? Colors.green.shade50.withOpacity(0.5) : AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: r.enabled ? Colors.green.shade200 : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(icon, style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                          r.label ?? r.type,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: r.enabled ? AppColors.textPrimary : AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.time,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: r.enabled ? Colors.green.shade800 : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class MealRemindersSheet extends ConsumerStatefulWidget {
  const MealRemindersSheet({super.key});

  @override
  ConsumerState<MealRemindersSheet> createState() => _MealRemindersSheetState();
}

class _MealRemindersSheetState extends ConsumerState<MealRemindersSheet> {
  Future<void> _pickTime(Reminder reminder) async {
    final parts = reminder.time.split(':');
    final initialHour = int.tryParse(parts[0]) ?? 12;
    final initialMinute = int.tryParse(parts[1]) ?? 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      UiFeedback.selection();
      final formattedTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      await ref.read(reminderServiceProvider).updateReminderTime(reminder.id, formattedTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminders = ref.watch(mealRemindersProvider);
    final reminderService = ref.read(reminderServiceProvider);

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recurring Meal Reminders',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Stay disciplined with automated daily notifications.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, color: AppColors.textTertiary),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Reminders List
            ...reminders.map((reminder) {
              final isBreakfast = reminder.type == 'breakfast';
              final isLunch = reminder.type == 'lunch';
              final emoji = isBreakfast ? '🥐' : (isLunch ? '🥗' : '🍲');

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: reminder.enabled
                      ? Colors.white
                      : AppColors.surfaceMuted.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: reminder.enabled
                        ? AppColors.primary.withOpacity(0.3)
                        : AppColors.border,
                  ),
                  boxShadow: reminder.enabled
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reminder.label ?? reminder.type,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                reminder.message ?? 'Daily logging reminder',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: reminder.enabled,
                          activeColor: AppColors.primary,
                          onChanged: (val) {
                            UiFeedback.selection();
                            reminderService.toggleReminder(reminder.id, val);
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 10),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () => _pickTime(reminder),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(LucideIcons.clock, size: 14, color: AppColors.textTertiary),
                                const SizedBox(width: 6),
                                Text(
                                  reminder.time,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(LucideIcons.edit2, size: 11, color: AppColors.textTertiary),
                              ],
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => reminderService.sendTestNotification(context, reminder),
                          icon: const Icon(LucideIcons.send, size: 12),
                          label: const Text('Test Alert', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
