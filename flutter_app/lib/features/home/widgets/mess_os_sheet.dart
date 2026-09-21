import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/models/scan_result.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/user_provider.dart';

class _MessMenuItemData {
  final String name;
  final int calories;
  final int protein;
  final int carbs;
  final int fats;
  final String hack;
  final String tag;

  const _MessMenuItemData({
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
    required this.hack,
    required this.tag,
  });
}

// Curated campus/hostel mess menu with practical swaps — ported from the
// web app's MessOSModal. Zero-friction logging: no photo, no typing, just tap.
const Map<String, List<_MessMenuItemData>> _messMenu = {
  'breakfast': [
    _MessMenuItemData(name: 'Poha with Roasted Peanuts', calories: 220, protein: 7, carbs: 36, fats: 7, hack: 'Add extra peanuts and lemon for iron absorption', tag: 'Energizer'),
    _MessMenuItemData(name: 'Idli & Sambar (3 pcs)', calories: 210, protein: 9, carbs: 42, fats: 2, hack: 'Skip white coconut chutney, drink extra bowl of hot sambar', tag: 'Low Fat'),
    _MessMenuItemData(name: 'Omelette with Brown Bread', calories: 280, protein: 19, carbs: 24, fats: 12, hack: 'Great high-protein campus breakfast', tag: 'Recovery'),
  ],
  'lunch': [
    _MessMenuItemData(name: 'Dal Tadka (Double Bowl)', calories: 210, protein: 16, carbs: 28, fats: 5, hack: 'Ask for minimal tadka oil and grab 2 bowls for 16g clean lentil protein', tag: 'High Protein Swap'),
    _MessMenuItemData(name: 'Roti with Ghee (2 pcs)', calories: 180, protein: 6, carbs: 34, fats: 4, hack: 'Limit to 2 rotis; prioritize dal and raw cucumber salad first', tag: 'Portion Control'),
    _MessMenuItemData(name: 'Paneer Bhurji / Soya Chunks', calories: 260, protein: 24, carbs: 8, fats: 16, hack: 'Best mess protein item; pair with cucumber slices', tag: 'Champion Pick'),
    _MessMenuItemData(name: 'Steamed Jeera Rice (Half Plate)', calories: 140, protein: 3, carbs: 30, fats: 1, hack: 'Eat half plate to keep afternoon sluggishness away', tag: 'Clean Carb'),
  ],
  'dinner': [
    _MessMenuItemData(name: 'Mixed Veg / Rajma Curry', calories: 240, protein: 14, carbs: 32, fats: 6, hack: 'Rajma is rich in potassium and slow-digesting protein', tag: 'Fiber Rich'),
    _MessMenuItemData(name: 'Curd / Buttermilk (Chaach)', calories: 80, protein: 6, carbs: 8, fats: 3, hack: 'Drink 1 glass of cold chaach with roasted jeera to aid digestion', tag: 'Gut Health'),
    _MessMenuItemData(name: 'Boiled Egg / Egg Curry (2 eggs)', calories: 190, protein: 18, carbs: 4, fats: 12, hack: 'Take eggs with less gravy to cut hidden mess refined oil', tag: 'Lean Protein'),
  ],
};

/// Home-screen entry point for MessOS — only shown to users who've marked
/// themselves as hostel/mess diners in Settings.
class MessOsBanner extends ConsumerWidget {
  const MessOsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userNotifierProvider).profile;
    if (profile?.isHostelUser != true) return const SizedBox.shrink();

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const MessOsSheet(),
        );
      },
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(colors: [Color(0xFF047857), Color(0xFF0F766E)]),
          boxShadow: [BoxShadow(color: const Color(0xFF047857).withOpacity(0.2), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
              child: const Icon(LucideIcons.utensilsCrossed, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('MessOS Campus Intelligence', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(999)),
                        child: const Text('HOSTEL ACTIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text("Today's lunch hacks, high-protein mess swaps & timings",
                      style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85))),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, color: Colors.white.withOpacity(0.7), size: 18),
          ],
        ),
      ),
    );
  }
}

class MessOsSheet extends ConsumerStatefulWidget {
  const MessOsSheet({super.key});

  @override
  ConsumerState<MessOsSheet> createState() => _MessOsSheetState();
}

class _MessOsSheetState extends ConsumerState<MessOsSheet> {
  String _selectedMeal = 'lunch';
  String? _loggedToast;

  Future<void> _handleQuickLog(_MessMenuItemData item) async {
    HapticFeedback.mediumImpact();
    try {
      final storage = ref.read(storageServiceProvider);
      await storage.saveScanResult(ScanResult(
        id: '',
        userId: '',
        foodName: item.name,
        type: 'food',
        calories: item.calories,
        protein: item.protein,
        carbs: item.carbs,
        fats: item.fats,
        confidence: 0.95,
        details: item.hack,
        description: 'Logged from MessOS Campus Assistant ($_selectedMeal)',
        timestamp: '',
      ));
      if (mounted) {
        setState(() => _loggedToast = 'Logged ${item.name} (+${item.calories} kcal)');
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (mounted) setState(() => _loggedToast = null);
        });
      }
    } catch (e) {
      debugPrint('Failed to log mess item: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _messMenu[_selectedMeal]!;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF047857), Color(0xFF0F766E)]),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                      child: const Icon(LucideIcons.utensilsCrossed, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MessOS Intelligence', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
                          Text('Nutrient optimization for hostel & college mess dining', style: TextStyle(fontSize: 11, color: Colors.white70)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ),

              // Meal tabs
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: ['breakfast', 'lunch', 'dinner'].map((meal) {
                    final isSelected = _selectedMeal == meal;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedMeal = meal);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: isSelected ? Border.all(color: AppColors.border) : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              meal[0].toUpperCase() + meal.substring(1),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? const Color(0xFF047857) : AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Items list
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(LucideIcons.lightbulb, size: 18, color: Colors.amber.shade800),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 12, height: 1.4, color: Colors.amber.shade900),
                                children: const [
                                  TextSpan(text: 'Hostel Pro-Tip: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                  TextSpan(text: 'Mess gravies contain high amounts of refined palm oil. Request dry sabzi or skim the surface layer to save 120-180 hidden calories per meal!'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...items.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(child: Text(item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFA7F3D0))),
                                            child: Text(item.tag, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                                          ),
                                          const SizedBox(height: 6),
                                          Text('"${item.hack}"', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.textTertiary, height: 1.3)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton.icon(
                                      onPressed: () => _handleQuickLog(item),
                                      icon: const Icon(LucideIcons.plusCircle, size: 14),
                                      label: const Text('Log', style: TextStyle(fontSize: 11)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF059669),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Container(height: 1, color: AppColors.border),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    _MacroPill(label: 'CAL', value: '${item.calories}', bg: const Color(0xFFF9FAFB), fg: AppColors.textPrimary),
                                    const SizedBox(width: 8),
                                    _MacroPill(label: 'PROT', value: '${item.protein}g', bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1E3A8A)),
                                    const SizedBox(width: 8),
                                    _MacroPill(label: 'CARB', value: '${item.carbs}g', bg: const Color(0xFFFFFBEB), fg: const Color(0xFF78350F)),
                                    const SizedBox(width: 8),
                                    _MacroPill(label: 'FAT', value: '${item.fats}g', bg: const Color(0xFFFFF1F2), fg: const Color(0xFF881337)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )),
                  ],
                ),
              ),

              // Logged toast
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _loggedToast != null
                    ? Container(
                        key: ValueKey(_loggedToast),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        color: const Color(0xFF059669),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.check, color: Colors.white, size: 14),
                            const SizedBox(width: 6),
                            Text(_loggedToast!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MacroPill extends StatelessWidget {
  final String label;
  final String value;
  final Color bg;
  final Color fg;

  const _MacroPill({required this.label, required this.value, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: fg.withOpacity(0.6))),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: fg)),
          ],
        ),
      ),
    );
  }
}
