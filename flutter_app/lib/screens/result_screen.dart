import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/scan_result.dart';
import '../providers/user_provider.dart';

class ResultScreen extends StatelessWidget {
  final ScanResult result;

  const ResultScreen({super.key, required this.result});

  String? _getPersonalizedTip(dynamic profile, dynamic dailySummary) {
    if (profile == null || dailySummary == null || result.type != 'food') return null;

    final remainingCalories = profile.calorieLimit - dailySummary.totalCalories;
    final isOverLimit = remainingCalories < 0;
    
    String tip = "";

    if (profile.goal == 'lose') {
      if (result.calories > 600) {
        tip = "This is a heavy meal for weight loss. Try to keep your next meal under 300 calories.";
      } else if (result.protein > 20) {
        tip = "Great choice! High protein helps maintain muscle while losing fat.";
      } else {
        tip = "Good portion control. Remember to stay hydrated!";
      }
    } else if (profile.goal == 'gain') {
      if (result.protein < 15) {
        tip = "You need more protein to build muscle. Consider adding a protein shake.";
      } else if (result.calories < 400) {
        tip = "This is a light meal. You might need a snack later to reach your surplus goal.";
      } else {
        tip = "Excellent calorie density for your bulking goal!";
      }
    }

    if (isOverLimit) {
      tip += " You've exceeded your daily limit, so focus on light activity like walking tonight.";
    } else if (remainingCalories < 200) {
      tip += " You're almost at your limit for today. Choose your next snack wisely!";
    }

    return tip;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final profile = userProvider.profile;
    final dailySummary = userProvider.dailySummary;
    final personalizedTip = _getPersonalizedTip(profile, dailySummary);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top Image Section
            Stack(
              children: [
                Container(
                  height: 420,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(120)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(120)),
                    child: Image.network(
                      result.imageUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(120)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.2),
                          Colors.transparent,
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 60,
                  left: 24,
                  child: _buildCircleButton(
                    LucideIcons.chevronLeft,
                    () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  top: 60,
                  right: 24,
                  child: _buildCircleButton(
                    LucideIcons.share2,
                    () => Share.share(
                      'NutriSnap Scan: ${result.foodName}\nCalories: ${result.calories} kcal\nProtein: ${result.protein}g\nCarbs: ${result.carbs}g\nFats: ${result.fats}g',
                    ),
                  ),
                ),
                Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'AI VERIFIED',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        result.foodName,
                        style: GoogleFonts.outfit(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Quick Stats
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildQuickStat('Calories', '${result.calories}', null),
                        _buildDivider(),
                        _buildQuickStat('Protein', '${result.protein}g', Colors.blue),
                        _buildDivider(),
                        _buildQuickStat('Carbs', '${result.carbs}g', Colors.orange),
                        _buildDivider(),
                        _buildQuickStat('Fats', '${result.fats}g', Colors.purple),
                      ],
                    ),
                  ).animate().fadeIn().moveY(begin: 20, end: 0),

                  const SizedBox(height: 32),

                  // Goal Comparison
                  if (profile != null) ...[
                    _buildSectionTitle('DAILY GOAL IMPACT'),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildGoalProgress('Protein', result.protein, dailySummary?.totalProtein ?? 0, profile.proteinGoal, Colors.blue),
                          const SizedBox(height: 24),
                          _buildGoalProgress('Carbs', result.carbs, dailySummary?.totalCarbs ?? 0, profile.carbsGoal, Colors.orange),
                          const SizedBox(height: 24),
                          _buildGoalProgress('Fats', result.fats, dailySummary?.totalFats ?? 0, profile.fatsGoal, Colors.purple),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms).moveY(begin: 20, end: 0),
                    const SizedBox(height: 32),
                  ],

                  // AI Insight
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(48),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(LucideIcons.sparkles, color: Color(0xFF10B981), size: 20),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'AI Insight',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          result.description ?? 'This meal provides a balanced mix of nutrients suitable for your daily intake.',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Colors.grey[700],
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (personalizedTip != null) ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.1)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('💡', style: TextStyle(fontSize: 20)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Tip: $personalizedTip',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: const Color(0xFF065F46),
                                      fontStyle: FontStyle.italic,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(delay: 400.ms).moveY(begin: 20, end: 0),

                  const SizedBox(height: 40),

                  // Action Buttons
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 72),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                      elevation: 8,
                    ),
                    child: Text(
                      'Back to Dashboard',
                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildQuickStat(String label, String value, Color? color) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: color ?? const Color(0xFF0F172A),
            letterSpacing: -1,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 8,
            fontWeight: FontWeight.w900,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 32, color: Colors.grey.withOpacity(0.1));
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Colors.grey,
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }

  Widget _buildGoalProgress(String label, int value, int total, int goal, Color color) {
    final progress = (total / goal).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                ),
                Text(
                  '+$value g from this meal',
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(progress * 100).round()}% of goal',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: color),
                ),
                Text(
                  '$total / $goal g',
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: const Color(0xFFF1F5F9),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
