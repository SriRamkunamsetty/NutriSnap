import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/models/scan_result.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/models/daily_summary.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/animated_entry.dart';
import '../../auth/providers/user_provider.dart';

class ResultScreen extends ConsumerStatefulWidget {
  final String id;
  const ResultScreen({super.key, required this.id});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  Future<void> _handleShare(ScanResult scan) async {
    HapticFeedback.lightImpact();
    
    final shareText = '''
🍎 NutriSnap Scan: \${scan.foodName}

\${(scan.type == 'food' || (scan.calories > 0)) ? 
  '🔥 Calories: \${scan.calories} kcal\\n💪 Protein: \${scan.protein}g\\n🍞 Carbs: \${scan.carbs}g\\n💧 Fats: \${scan.fats}g\\n\\n' : 
  '🤖 AI detected: \${scan.type} (\${scan.details})\\n\\n'}
Track your journey with NutriSnap!
''';

    try {
      await Clipboard.setData(ClipboardData(text: shareText));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to copy to clipboard')));
    }
  }

  String? _getPersonalizedTip(UserProfile? profile, DailySummary? dailySummary, ScanResult scan) {
    if (profile == null || dailySummary == null || scan.type != 'food') return null;

    final remainingCalories = (profile.calorieLimit) - dailySummary.totalCalories;
    final isOverLimit = remainingCalories < 0;
    
    String tip = "";

    if (profile.goal == Goal.lose) {
      if (scan.calories > 600) {
        tip = "This is a heavy meal for weight loss. Try to keep your next meal under 300 calories.";
      } else if (scan.protein > 20) {
        tip = "Great choice! High protein helps maintain muscle while losing fat.";
      } else {
        tip = "Good portion control. Remember to stay hydrated!";
      }
    } else if (profile.goal == Goal.gain) {
      if (scan.protein < 15) {
        tip = "You need more protein to build muscle. Consider adding a protein shake.";
      } else if (scan.calories < 400) {
        tip = "This is a light meal. You might need a snack later to reach your surplus goal.";
      } else {
        tip = "Excellent calorie density for your bulking goal!";
      }
    } else {
      if (scan.calories > 800) {
        tip = "It is quite calorie-dense, so consider balancing your next meal with lighter options.";
      } else {
        tip = "It fits perfectly within your daily calorie budget.";
      }
    }

    if (isOverLimit) {
      tip += " You've exceeded your daily limit, so focus on light activity like walking tonight.";
    } else if (remainingCalories < 200) {
      tip += " You're almost at your limit for today. Choose your next snack wisely!";
    }

    return tip.isNotEmpty ? tip : null;
  }

  void _showEditModal(ScanResult scan) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Edit Modal',
      pageBuilder: (context, anim1, anim2) => _EditLogModal(
        scan: scan,
        onLogSubmit: (updatedScan) async {
          Navigator.of(context).pop();
          await ref.read(storageServiceProvider).updateScanResult(updatedScan);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan updated!')));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncScans = ref.watch(scanHistoryStreamProvider);
    final userState = ref.watch(userNotifierProvider);
    final dailySummarySync = ref.watch(dailySummaryStreamProvider).valueOrNull;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: asyncScans.when(
        data: (scans) {
          final scan = scans.where((s) => s.id == widget.id).firstOrNull;
          
          if (scan == null) {
            return _buildNotFound();
          }
          
          return _buildContent(scan, userState.profile, dailySummarySync);
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, st) => Center(child: Text('Error loading scan: $e')),
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border)),
              child: const Icon(LucideIcons.info, size: 48, color: Colors.red),
            ),
            const SizedBox(height: 32),
            const Text('Scan Not Found', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('We couldn\\'t find the details for this scan. It might have been deleted.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.home),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              child: const Text('Back to Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ScanResult scan, UserProfile? profile, DailySummary? dailySummary) {
    final isFood = scan.type == 'food' || scan.calories > 0;
    final tip = _getPersonalizedTip(profile, dailySummary, scan);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        children: [
          // Header Image Section
          SizedBox(
            height: 420,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipPath(
                  clipper: _CurveClipper(),
                  child: CachedNetworkImage(
                    imageUrl: scan.imageUrl ?? 'https://picsum.photos/seed/food/400/400',
                    fit: BoxFit.cover,
                  ),
                ),
                ClipPath(
                  clipper: _CurveClipper(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withOpacity(0.8), Colors.black.withOpacity(0.2), Colors.transparent],
                      )
                    ),
                  ),
                ),
                SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        top: 16, left: 16,
                        child: InkWell(
                          onTap: () => context.go(AppRoutes.home),
                          child: Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.3))), child: const Icon(LucideIcons.chevronLeft, color: Colors.white)),
                        )
                      ),
                      Positioned(
                        top: 16, right: 16,
                        child: InkWell(
                          onTap: () => _handleShare(scan),
                          child: Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.3))), child: const Icon(LucideIcons.share2, color: Colors.white, size: 20)),
                        )
                      ),
                      Positioned(
                        bottom: 48, left: 0, right: 0,
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(24)),
                                  child: Text(isFood ? 'AI VERIFIED' : 'AI DETECTED', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.3))),
                                  child: Row(
                                    children: [
                                      Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(2)), child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: scan.confidence, child: Container(decoration: BoxDecoration(color: Colors.greenAccent, borderRadius: BorderRadius.circular(2))))),
                                      const SizedBox(width: 8),
                                      Text('\${(scan.confidence * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                ),
                              ],
                            ).animate().slideY(begin: 0.5, end: 0, duration: 400.ms).fadeIn(),
                            const SizedBox(height: 8),
                            Text(scan.foodName, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1.0)).animate().slideY(begin: 0.5, end: 0, duration: 500.ms).fadeIn(),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Quick Stats
          if (isFood)
            Transform.translate(
              offset: const Offset(0, -32),
              child: AnimatedFadeSlide(
                delay: const Duration(milliseconds: 100),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildQuickMacro(scan.calories.toString(), 'Calories', AppColors.textPrimary),
                      Container(width: 1, height: 32, color: AppColors.border),
                      _buildQuickMacro('\${scan.protein}g', 'Protein', Colors.blue.shade600),
                      Container(width: 1, height: 32, color: AppColors.border),
                      _buildQuickMacro('\${scan.carbs}g', 'Carbs', Colors.orange.shade600),
                      Container(width: 1, height: 32, color: AppColors.border),
                      _buildQuickMacro('\${scan.fats}g', 'Fats', Colors.purple.shade600),
                    ],
                  ),
                ),
              ),
            ),
            
          if (!isFood)
            Transform.translate(
              offset: const Offset(0, -32),
              child: AnimatedFadeSlide(
                delay: const Duration(milliseconds: 100),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildQuickMacroCat(scan.type, 'Category', LucideIcons.fingerprint, Colors.blue),
                      Container(width: 1, height: 32, color: AppColors.border),
                      _buildQuickMacroCat(scan.details ?? 'Unknown', 'Details', LucideIcons.checkCircle, Colors.green),
                      Container(width: 1, height: 32, color: AppColors.border),
                      _buildQuickMacroCat('\${(scan.confidence * 100).round()}%', 'Confidence', LucideIcons.flame, Colors.orange),
                    ],
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                // Edit Button (Added per request)
                if (isFood)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: OutlinedButton.icon(
                      onPressed: () => _showEditModal(scan),
                      icon: const Icon(LucideIcons.edit2, size: 16),
                      label: const Text('Edit / Correct Values'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        side: const BorderSide(color: AppColors.borderDark),
                      ),
                    ),
                  ),

                if (isFood) _buildDetailedMacros(scan),
                if (isFood && profile != null) ...[
                  const SizedBox(height: 24),
                  _buildGoalImpactCard(scan, profile, dailySummary),
                ],

                const SizedBox(height: 24),

                // Generative Insights
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(48), border: Border.all(color: AppColors.border)),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16)), child: Icon(LucideIcons.check, color: Colors.green.shade600, size: 20)),
                          const SizedBox(width: 12),
                          const Text('AI Insight', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (isFood) ...[
                         Text(
                          'This meal is \${scan.protein > 20 ? 'excellent for muscle recovery due to its high protein content' : 'a balanced choice for your daily intake'}. '
                          '\${scan.calories > 800 ? ' It is quite calorie-dense, so consider balancing your next meal with lighter options.' : ' It fits perfectly within your daily calorie budget.'}',
                          style: const TextStyle(fontSize: 16, color: AppColors.textSecondary, height: 1.5, fontWeight: FontWeight.w500),
                        ),
                        if (tip != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.green.shade100)),
                            child: Text('💡 Tip: $tip', style: TextStyle(color: Colors.green.shade800, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
                          ),
                        ]
                      ] else ...[
                        const Text('Our AI has analyzed this image and detected the following:', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.border)),
                          child: Text('"\${scan.description}"', style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary, height: 1.5)),
                        ),
                      ]
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    context.go(AppRoutes.home);
                  },
                  icon: const Icon(LucideIcons.home, size: 20),
                  label: const Text('Back to Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedMacros(ScanResult scan) {
    return Row(
      children: [
        _buildDetailedMacroCard('Protein', scan.protein, 'g', LucideIcons.beef, Colors.blue),
        const SizedBox(width: 12),
        _buildDetailedMacroCard('Carbs', scan.carbs, 'g', LucideIcons.wheat, Colors.orange),
        const SizedBox(width: 12),
        _buildDetailedMacroCard('Fats', scan.fats, 'g', LucideIcons.droplets, Colors.purple),
      ],
    );
  }

  Widget _buildDetailedMacroCard(String label, int value, String unit, IconData icon, MaterialColor color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.border)),
        child: Column(
          children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: color.shade600, size: 20)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value.toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                Text(unit, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 2),
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalImpactCard(ScanResult scan, UserProfile profile, DailySummary? dailySummary) {
    final dailyCals = dailySummary?.totalCalories ?? 0;
    final limitCals = profile.calorieLimit;
    final isOver = dailyCals > limitCals;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: isOver ? Colors.red.shade50.withOpacity(0.3) : Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: isOver ? Colors.red.shade200 : AppColors.border)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('DAILY GOAL IMPACT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
              if (isOver)
                Row(
                  children: [
                    Icon(LucideIcons.flame, size: 14, color: Colors.red.shade500),
                    const SizedBox(width: 4),
                    Text('LIMIT EXCEEDED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.red.shade500, letterSpacing: 1.0)),
                  ],
                ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 500.ms),
            ],
          ),
          if (isOver) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.red.shade100)),
              child: Row(
                children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.red.shade500, borderRadius: BorderRadius.circular(16)), child: const Icon(LucideIcons.flame, color: Colors.white, size: 20)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Text(((dailyCals - scan.calories) <= limitCals) ? 'This meal pushed you over!' : 'Daily Limit Exceeded', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.red.shade900)),
                         const SizedBox(height: 4),
                         Text('Your total is now $dailyCals kcal. You are ${dailyCals - limitCals} kcal over target.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          _buildImpactRow('Protein', scan.protein, dailySummary?.totalProtein ?? 0, profile.proteinGoal, Colors.blue),
          const SizedBox(height: 16),
          _buildImpactRow('Carbs', scan.carbs, dailySummary?.totalCarbs ?? 0, profile.carbsGoal, Colors.orange),
          const SizedBox(height: 16),
          _buildImpactRow('Fats', scan.fats, dailySummary?.totalFats ?? 0, profile.fatsGoal, Colors.purple),
        ],
      ),
    );
  }

  Widget _buildImpactRow(String label, int valueAdded, int currentTotal, int goal, MaterialColor color) {
    final percTotal = (currentTotal / goal).clamp(0.0, 1.0);
    final previousTotal = (currentTotal - valueAdded).clamp(0, goal);
    final percPrev = (previousTotal / goal).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                Text('+$valueAdded g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: AppColors.textTertiary)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\${(percTotal * 100).round()}% of goal', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: (percTotal >= 1.0) ? Colors.blue.shade600 : Colors.green.shade600)),
                Text('$currentTotal / $goal g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: AppColors.textTertiary)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 12,
          decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(6)),
          child: Stack(
            children: [
              FractionallySizedBox(widthFactor: percPrev, child: Container(decoration: BoxDecoration(color: color.shade200, borderRadius: BorderRadius.circular(6)))),
              FractionallySizedBox(widthFactor: percTotal, child: Container(decoration: BoxDecoration(color: color.shade500, borderRadius: BorderRadius.only(topRight: const Radius.circular(6), bottomRight: const Radius.circular(6))))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickMacro(String value, String label, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color, letterSpacing: -1.0)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
      ],
    );
  }

  Widget _buildQuickMacroCat(String value, String label, IconData icon, MaterialColor color) {
     return Column(
      children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color.shade600, size: 20)),
        const SizedBox(height: 8),
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ],
    );
  }
}

class _CurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 60);
    path.quadraticBezierTo(size.width / 2, size.height + 20, size.width, size.height - 60);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }
  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// ---------------------------------------------------------
// EDIT MODAL 
// ---------------------------------------------------------
class _EditLogModal extends StatefulWidget {
  final ScanResult scan;
  final Function(ScanResult) onLogSubmit;
  const _EditLogModal({required this.scan, required this.onLogSubmit});

  @override
  State<_EditLogModal> createState() => _EditLogModalState();
}

class _EditLogModalState extends State<_EditLogModal> {
  late TextEditingController _nameCtrl;
  late TextEditingController _calCtrl;
  late TextEditingController _proCtrl;
  late TextEditingController _carbCtrl;
  late TextEditingController _fatCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.scan.foodName);
    _calCtrl = TextEditingController(text: widget.scan.calories.toString());
    _proCtrl = TextEditingController(text: widget.scan.protein.toString());
    _carbCtrl = TextEditingController(text: widget.scan.carbs.toString());
    _fatCtrl = TextEditingController(text: widget.scan.fats.toString());
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) return;
    
    final updated = widget.scan.copyWith(
      foodName: _nameCtrl.text.trim(),
      calories: int.tryParse(_calCtrl.text) ?? widget.scan.calories,
      protein: int.tryParse(_proCtrl.text) ?? widget.scan.protein,
      carbs: int.tryParse(_carbCtrl.text) ?? widget.scan.carbs,
      fats: int.tryParse(_fatCtrl.text) ?? widget.scan.fats,
    );
    
    widget.onLogSubmit(updated);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(0.4),
        body: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Center(
            child: GestureDetector(
              onTap: () {}, 
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Edit Meal', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                        IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(LucideIcons.x, color: AppColors.textTertiary)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: 'Meal Name', filled: true, fillColor: AppColors.surfaceMuted, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _calCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Calories', filled: true, fillColor: AppColors.surfaceMuted, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
                        const SizedBox(width: 16),
                        Expanded(child: TextField(controller: _proCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Protein (g)', filled: true, fillColor: AppColors.surfaceMuted, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _carbCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Carbs (g)', filled: true, fillColor: AppColors.surfaceMuted, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
                        const SizedBox(width: 16),
                        Expanded(child: TextField(controller: _fatCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Fats (g)', filled: true, fillColor: AppColors.surfaceMuted, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: _submit, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))), child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
