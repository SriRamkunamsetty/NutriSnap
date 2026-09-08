import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/models/scan_result.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/models/daily_summary.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ui_feedback.dart';

class HealthyFoodItem {
  final String id;
  final String foodName;
  final String category; // 'high_protein' | 'low_carb' | 'snack' | 'balanced'
  final String description;
  final int calories;
  final int protein;
  final int carbs;
  final int fats;
  final String iconEmoji;
  final List<String> tags;
  final String mealType; // 'breakfast' | 'lunch' | 'dinner' | 'snack'

  const HealthyFoodItem({
    required this.id,
    required this.foodName,
    required this.category,
    required this.description,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.iconEmoji,
    required this.tags,
    required this.mealType,
  });
}

const List<HealthyFoodItem> _suggestedFoodCatalog = [
  // High Protein
  HealthyFoodItem(
    id: 'sug_1',
    foodName: 'Greek Yogurt & Blueberries',
    category: 'high_protein',
    description: 'Creamy non-fat Greek yogurt with antioxidant blueberries & honey drizzle.',
    calories: 180,
    protein: 18,
    carbs: 22,
    fats: 2,
    iconEmoji: '🫐',
    tags: ['High Protein', 'Under 200 kcal'],
    mealType: 'breakfast',
  ),
  HealthyFoodItem(
    id: 'sug_2',
    foodName: 'Grilled Lemon Herb Chicken Bowl',
    category: 'high_protein',
    description: 'Juicy chicken breast over seasoned quinoa, cucumber, and fresh spinach.',
    calories: 420,
    protein: 45,
    carbs: 32,
    fats: 10,
    iconEmoji: '🍗',
    tags: ['45g Protein', 'Clean Fuel'],
    mealType: 'lunch',
  ),
  HealthyFoodItem(
    id: 'sug_3',
    foodName: 'Baked Atlantic Salmon & Greens',
    category: 'high_protein',
    description: 'Rich in Omega-3 fatty acids paired with steamed asparagus & lemon.',
    calories: 440,
    protein: 38,
    carbs: 8,
    fats: 26,
    iconEmoji: '🐟',
    tags: ['Omega-3', 'High Protein'],
    mealType: 'dinner',
  ),

  // Low Carb
  HealthyFoodItem(
    id: 'sug_4',
    foodName: 'Avocado & Poached Egg Plate',
    category: 'low_carb',
    description: 'Cage-free eggs with fresh Haas avocado and chili flakes.',
    calories: 280,
    protein: 14,
    carbs: 8,
    fats: 22,
    iconEmoji: '🥑',
    tags: ['Keto Friendly', 'Healthy Fats'],
    mealType: 'breakfast',
  ),
  HealthyFoodItem(
    id: 'sug_5',
    foodName: 'Mediterranean Tuna Salad',
    category: 'low_carb',
    description: 'Flaked albacore tuna with crisp celery, Kalamata olives & olive oil.',
    calories: 290,
    protein: 34,
    carbs: 4,
    fats: 14,
    iconEmoji: '🥗',
    tags: ['Low Carb', '34g Protein'],
    mealType: 'lunch',
  ),
  HealthyFoodItem(
    id: 'sug_6',
    foodName: 'Zucchini Noodles with Garlic Prawns',
    category: 'low_carb',
    description: 'Spiralized zucchini tossed with garlic shrimp and shaved parmesan.',
    calories: 310,
    protein: 30,
    carbs: 9,
    fats: 16,
    iconEmoji: '🍤',
    tags: ['Low Carb', 'Low Calorie'],
    mealType: 'dinner',
  ),

  // Snacks (< 200 kcal)
  HealthyFoodItem(
    id: 'sug_7',
    foodName: 'Crisp Green Apple with Almond Butter',
    category: 'snack',
    description: 'Crisp Granny Smith slices paired with organic raw almond butter.',
    calories: 190,
    protein: 5,
    carbs: 24,
    fats: 9,
    iconEmoji: '🍏',
    tags: ['Natural Energy', 'Under 200 kcal'],
    mealType: 'snack',
  ),
  HealthyFoodItem(
    id: 'sug_8',
    foodName: 'Steamed Edamame with Sea Salt',
    category: 'snack',
    description: 'Plant-based complete protein pods lightly sprinkled with mineral salt.',
    calories: 140,
    protein: 12,
    carbs: 10,
    fats: 4,
    iconEmoji: '🫛',
    tags: ['Plant Protein', '140 kcal'],
    mealType: 'snack',
  ),
  HealthyFoodItem(
    id: 'sug_9',
    foodName: 'Cottage Cheese & Walnuts',
    category: 'snack',
    description: 'Slow-digesting casein protein topped with heart-healthy walnuts.',
    calories: 170,
    protein: 16,
    carbs: 6,
    fats: 9,
    iconEmoji: '🧀',
    tags: ['Satiety Boost', 'High Protein'],
    mealType: 'snack',
  ),
];

class HealthyFoodSuggestions extends ConsumerStatefulWidget {
  final DailySummary? dailySummary;
  final UserProfile? profile;
  final Function(ScanResult) onQuickLog;

  const HealthyFoodSuggestions({
    super.key,
    required this.dailySummary,
    required this.profile,
    required this.onQuickLog,
  });

  @override
  ConsumerState<HealthyFoodSuggestions> createState() => _HealthyFoodSuggestionsState();
}

class _HealthyFoodSuggestionsState extends ConsumerState<HealthyFoodSuggestions> {
  String _selectedFilter = 'for_you'; // 'for_you' | 'high_protein' | 'low_carb' | 'snack'

  String _getMealTimeContext() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return 'breakfast';
    if (hour >= 11 && hour < 16) return 'lunch';
    if (hour >= 16 && hour < 21) return 'dinner';
    return 'snack';
  }

  List<HealthyFoodItem> _getFilteredSuggestions() {
    final int target = widget.profile?.calorieLimit ?? 2000;
    final int consumed = widget.dailySummary?.totalCalories ?? 0;
    final int remaining = math.max(0, target - consumed);
    final String currentMeal = _getMealTimeContext();

    if (_selectedFilter == 'for_you') {
      // Smart recommendation based on remaining calorie budget & goal
      final goal = widget.profile?.goal ?? Goal.lose;

      final sorted = List<HealthyFoodItem>.from(_suggestedFoodCatalog);
      sorted.sort((a, b) {
        // Prioritize items that fit within remaining calories
        final aFits = a.calories <= (remaining > 0 ? remaining : 300) ? 1 : 0;
        final bFits = b.calories <= (remaining > 0 ? remaining : 300) ? 1 : 0;
        if (aFits != bFits) return bFits.compareTo(aFits);

        // Prioritize current meal time
        final aMealMatch = a.mealType == currentMeal ? 1 : 0;
        final bMealMatch = b.mealType == currentMeal ? 1 : 0;
        if (aMealMatch != bMealMatch) return bMealMatch.compareTo(aMealMatch);

        // If weight loss, prioritize high protein/low calorie
        if (goal == Goal.lose) {
          final aRatio = a.protein / math.max(1, a.calories);
          final bRatio = b.protein / math.max(1, b.calories);
          return bRatio.compareTo(aRatio);
        }

        return a.calories.compareTo(b.calories);
      });

      return sorted.take(5).toList();
    }

    return _suggestedFoodCatalog
        .where((item) => item.category == _selectedFilter)
        .toList();
  }

  void _showDetailsSheet(HealthyFoodItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _HealthyItemDetailSheet(
        item: item,
        remainingCalories: math.max(
          0,
          (widget.profile?.calorieLimit ?? 2000) -
              (widget.dailySummary?.totalCalories ?? 0),
        ),
        onLog: (multiplier) {
          Navigator.of(context).pop();
          _logSuggestedItem(item, multiplier: multiplier);
        },
      ),
    );
  }

  void _logSuggestedItem(HealthyFoodItem item, {double multiplier = 1.0}) {
    UiFeedback.medium();
    final scan = ScanResult(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      userId: widget.profile?.uid ?? '',
      timestamp: DateTime.now().toIso8601String(),
      foodName: item.foodName,
      type: 'food',
      confidence: 1.0,
      description: item.description,
      calories: (item.calories * multiplier).round(),
      protein: (item.protein * multiplier).round(),
      carbs: (item.carbs * multiplier).round(),
      fats: (item.fats * multiplier).round(),
    );

    widget.onQuickLog(scan);
  }

  @override
  Widget build(BuildContext context) {
    final int target = widget.profile?.calorieLimit ?? 2000;
    final int consumed = widget.dailySummary?.totalCalories ?? 0;
    final int remaining = math.max(0, target - consumed);
    final suggestions = _getFilteredSuggestions();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(LucideIcons.sparkles, size: 18, color: Colors.green.shade700),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Suggested Healthy Foods',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'BASED ON $remaining KCAL BUDGET REMAINING',
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade100),
                ),
                child: Text(
                  '${widget.profile?.goal?.name.toUpperCase() ?? "FITNESS"} GOAL',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: Colors.green.shade800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Filter Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('for_you', '✨ For You (Optimal)'),
                const SizedBox(width: 8),
                _buildFilterChip('high_protein', '💪 High Protein'),
                const SizedBox(width: 8),
                _buildFilterChip('low_carb', '🥑 Low Carb'),
                const SizedBox(width: 8),
                _buildFilterChip('snack', '🍏 Light Snacks'),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Suggestion Cards Carousel / List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = suggestions[index];
              final double budgetShare = remaining > 0
                  ? ((item.calories / remaining) * 100).clamp(0, 100)
                  : 100;

              return InkWell(
                onTap: () => _showDetailsSheet(item),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black.withOpacity(0.04)),
                  ),
                  child: Row(
                    children: [
                      // Emoji / Thumbnail Avatar
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            item.iconEmoji,
                            style: const TextStyle(fontSize: 26),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Information
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.foodName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  '${item.calories} kcal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '• ${budgetShare.round()}% of left budget',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Macro pills
                            Row(
                              children: [
                                _buildMiniMacro('P: ${item.protein}g', Colors.blue.shade700, Colors.blue.shade50),
                                const SizedBox(width: 4),
                                _buildMiniMacro('C: ${item.carbs}g', Colors.orange.shade800, Colors.orange.shade50),
                                const SizedBox(width: 4),
                                _buildMiniMacro('F: ${item.fats}g', Colors.purple.shade700, Colors.purple.shade50),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Quick Log Button
                      InkWell(
                        onTap: () => _logSuggestedItem(item),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.plus, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Log',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final bool isSelected = _selectedFilter == key;
    return InkWell(
      onTap: () {
        UiFeedback.selection();
        setState(() => _selectedFilter = key);
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.textPrimary : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMiniMacro(String text, Color textCol, Color bgCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textCol),
      ),
    );
  }
}

class _HealthyItemDetailSheet extends StatefulWidget {
  final HealthyFoodItem item;
  final int remainingCalories;
  final Function(double multiplier) onLog;

  const _HealthyItemDetailSheet({
    required this.item,
    required this.remainingCalories,
    required this.onLog,
  });

  @override
  State<_HealthyItemDetailSheet> createState() => _HealthyItemDetailSheetState();
}

class _HealthyItemDetailSheetState extends State<_HealthyItemDetailSheet> {
  double _portionMultiplier = 1.0;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final int cal = (item.calories * _portionMultiplier).round();
    final int pro = (item.protein * _portionMultiplier).round();
    final int carb = (item.carbs * _portionMultiplier).round();
    final int fat = (item.fats * _portionMultiplier).round();

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
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
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Text(item.iconEmoji, style: const TextStyle(fontSize: 30)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.foodName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Portion Multiplier
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Portion Size:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary),
                ),
                Row(
                  children: [0.5, 1.0, 1.5].map((m) {
                    final bool isCur = _portionMultiplier == m;
                    return InkWell(
                      onTap: () {
                        UiFeedback.selection();
                        setState(() => _portionMultiplier = m);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isCur ? AppColors.primary : AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${m}x',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isCur ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Nutritional Highlights
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Calories', '$cal', 'kcal', AppColors.primary),
                  _buildStat('Protein', '$pro', 'g', Colors.blue.shade600),
                  _buildStat('Carbs', '$carb', 'g', Colors.orange.shade600),
                  _buildStat('Fats', '$fat', 'g', Colors.purple.shade600),
                ],
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () => widget.onLog(_portionMultiplier),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: Text(
                  'Log This Meal ($cal kcal)',
                  style: const TextStyle(
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

  Widget _buildStat(String label, String value, String unit, Color color) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
            Text(unit, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
          ],
        ),
      ],
    );
  }
}
