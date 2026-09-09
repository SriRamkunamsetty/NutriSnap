import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/models/daily_summary.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/theme/app_colors.dart';

class CalorieProgressRing extends StatelessWidget {
  final DailySummary? dailySummary;
  final UserProfile? profile;
  final double progress;

  const CalorieProgressRing({
    super.key,
    required this.dailySummary,
    required this.profile,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final int consumed = dailySummary?.totalCalories ?? 0;
    final int target = (profile?.calorieLimit != null && profile!.calorieLimit! > 0)
        ? profile!.calorieLimit!
        : 2000;
    final int remaining = math.max(0, target - consumed);
    final bool isOver = consumed > target;
    final int overAmount = isOver ? (consumed - target) : 0;
    final double clampedProgress = progress.clamp(0.0, 1.5);
    final double pct = (progress * 100);

    // Color states
    final Color primaryColor = isOver
        ? const Color(0xFFEF4444)
        : (progress >= 0.85
            ? const Color(0xFFF59E0B)
            : AppColors.primary);

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fadeOut(duration: 1.seconds),
                  const SizedBox(width: 8),
                  const Text(
                    'DAILY FUEL & TARGET',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textTertiary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isOver ? Colors.red.shade50 : (progress >= 0.85 ? Colors.amber.shade50 : Colors.green.shade50),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isOver ? Colors.red.shade100 : (progress >= 0.85 ? Colors.amber.shade100 : Colors.green.shade100),
                  ),
                ),
                child: Text(
                  isOver ? '+$overAmount kcal over' : '${pct.round()}% of goal',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: isOver ? Colors.red.shade700 : (progress >= 0.85 ? Colors.amber.shade800 : Colors.green.shade700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Central Visual: Progress Ring + Calorie Numerical Overview
          Row(
            children: [
              // Radial Progress Ring
              SizedBox(
                width: 104,
                height: 104,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background track
                    CustomPaint(
                      size: const Size(104, 104),
                      painter: _RingPainter(
                        progress: 1.0,
                        color: AppColors.surfaceMuted,
                        strokeWidth: 10,
                      ),
                    ),
                    // Foreground animated progress
                    CustomPaint(
                      size: const Size(104, 104),
                      painter: _RingPainter(
                        progress: math.min(clampedProgress, 1.0),
                        color: primaryColor,
                        strokeWidth: 10,
                        isOver: isOver,
                      ),
                    ),
                    // Center Content
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOver ? LucideIcons.alertTriangle : LucideIcons.flame,
                          size: 20,
                          color: primaryColor,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${pct.round()}%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: isOver ? Colors.red.shade700 : AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 24),

              // Numerical Metrics & Goal status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$consumed',
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            letterSpacing: -1.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '/ $target kcal',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOver ? Colors.red.shade50 : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOver ? LucideIcons.alertCircle : LucideIcons.checkCircle2,
                            size: 13,
                            color: isOver ? Colors.red.shade600 : AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isOver
                                ? 'Exceeded by $overAmount kcal'
                                : '$remaining kcal remaining today',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isOver ? Colors.red.shade700 : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Horizontal Progress Bar
          Container(
            height: 10,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: math.min(clampedProgress, 1.0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Macronutrient Breakdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMacroItem(
                label: 'Protein',
                current: dailySummary?.totalProtein ?? 0,
                target: profile?.proteinGoal ?? 150,
                color: Colors.blue.shade600,
                icon: LucideIcons.zap,
              ),
              _buildMacroItem(
                label: 'Carbs',
                current: dailySummary?.totalCarbs ?? 0,
                target: profile?.carbsGoal ?? 200,
                color: Colors.orange.shade600,
                icon: LucideIcons.wheat,
              ),
              _buildMacroItem(
                label: 'Fats',
                current: dailySummary?.totalFats ?? 0,
                target: profile?.fatsGoal ?? 70,
                color: Colors.purple.shade600,
                icon: LucideIcons.droplet,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroItem({
    required String label,
    required int current,
    required int target,
    required Color color,
    required IconData icon,
  }) {
    final double macroPct = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.03)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$current',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '/$target g',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 4,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: macroPct,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
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

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final bool isOver;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    this.isOver = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Start from top (-90 degrees)
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
