import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/models/scan_result.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/models/daily_summary.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/widgets/scan_image.dart';
import '../../scan/screens/scan_review_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/animated_entry.dart';
import '../../auth/providers/user_provider.dart';

class ResultScreen extends ConsumerStatefulWidget {
  final String id;
  final ScanResult? initialScan;
  const ResultScreen({super.key, required this.id, this.initialScan});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  ScanResult? _fetchedScan;
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    _fetchedScan = widget.initialScan;
    _checkAndFetchScan();
  }

  Future<void> _checkAndFetchScan() async {
    // If we have initial scan or it's in history, we don't need to fetch
    final scans = ref.read(scanHistoryStreamProvider).valueOrNull ?? [];
    if (_fetchedScan != null || scans.any((s) => s.id == widget.id)) return;

    setState(() => _isFetching = true);
    final scan = await ref.read(scanRepositoryProvider).getById(widget.id);
    if (mounted) {
      setState(() {
        _fetchedScan = scan;
        _isFetching = false;
      });
    }
  }

  Future<void> _handleDelete(ScanResult scan) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Scan?'),
        content: const Text('This action cannot be undone and will remove the nutritional data from your daily summary.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(scanRepositoryProvider).delete(scan.id);
      if (mounted) {
        context.go(AppRoutes.home);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan deleted')));
      }
    }
  }

  Future<void> _handleShare(ScanResult scan) async {
    HapticFeedback.lightImpact();
    
    final isFood = scan.type == 'food' || scan.calories > 0;
    final shareText = StringBuffer('🍎 NutriSnap: ${scan.foodName}\n\n');
    if (isFood) {
      shareText
        ..writeln('🔥 Calories: ${scan.calories} kcal')
        ..writeln('💪 Protein: ${scan.protein} g')
        ..writeln('🍞 Carbs: ${scan.carbs} g')
        ..writeln('💧 Fats: ${scan.fats} g');
    } else {
      shareText.writeln('🤖 AI detected: ${scan.type} (${scan.details ?? ''})');
    }
    shareText.write('\nTracked privately with NutriSnap AI');

    try {
      await SharePlus.instance.share(ShareParams(text: shareText.toString()));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the share sheet')));
      }
    }
  }

  String? _getPersonalizedTip(UserProfile? profile, DailySummary? dailySummary, ScanResult scan) {
    if (profile == null || dailySummary == null || scan.type != 'food') return null;

    final remainingCalories = (profile.calorieLimit ?? 2000) - dailySummary.totalCalories;
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

  Future<void> _showEditModal(ScanResult scan) async {
    // Same editor as the scan review: edit foods, portions and nutrition.
    await context.push(AppRoutes.scanReview, extra: ScanReviewArgs.edit(scan));
    if (!mounted) return;
    final fresh = await ref.read(scanRepositoryProvider).getById(scan.id);
    if (mounted && fresh != null) setState(() => _fetchedScan = fresh);
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
          final scan = scans.where((s) => s.id == widget.id).firstOrNull ?? _fetchedScan;
          
          if (scan == null) {
            if (_isFetching) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }
            return _buildNotFound();
          }
          
          return _buildContent(scan, userState.profile, dailySummarySync);
        },
        loading: () {
          if (_fetchedScan != null) {
            return _buildContent(_fetchedScan!, userState.profile, dailySummarySync);
          }
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        },
        error: (e, st) {
          if (_fetchedScan != null) {
             return _buildContent(_fetchedScan!, userState.profile, dailySummarySync);
          }
          return Center(child: Text('Error loading scan: $e'));
        },
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
            const Text('We couldn\'t find the details for this scan. It might have been deleted.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
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
                  child: ScanImage(path: scan.imageUrl),
                ),
                ClipPath(
                  clipper: _CurveClipper(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withValues(alpha: 0.8), Colors.black.withValues(alpha: 0.2), Colors.transparent],
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
                          child: Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.3))), child: const Icon(LucideIcons.chevronLeft, color: Colors.white)),
                        )
                      ),
                      Positioned(
                        top: 16, right: 16,
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => _handleShare(scan),
                              child: Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.3))), child: const Icon(LucideIcons.share2, color: Colors.white, size: 20)),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: () => _handleDelete(scan),
                              child: Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.4), shape: BoxShape.circle, border: Border.all(color: Colors.red.withValues(alpha: 0.3))), child: const Icon(LucideIcons.trash2, color: Colors.white, size: 20)),
                            ),
                          ],
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
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
                                  child: Row(
                                    children: [
                                      Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)), child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: scan.confidence, child: Container(decoration: BoxDecoration(color: Colors.greenAccent, borderRadius: BorderRadius.circular(2))))),
                                      const SizedBox(width: 8),
                                      Text('${(scan.confidence * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
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
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildQuickMacro(scan.calories.toString(), 'Calories', AppColors.textPrimary),
                      Container(width: 1, height: 32, color: AppColors.border),
                      _buildQuickMacro('${scan.protein}g', 'Protein', Colors.blue.shade600),
                      Container(width: 1, height: 32, color: AppColors.border),
                      _buildQuickMacro('${scan.carbs}g', 'Carbs', Colors.orange.shade600),
                      Container(width: 1, height: 32, color: AppColors.border),
                      _buildQuickMacro('${scan.fats}g', 'Fats', Colors.purple.shade600),
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
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildQuickMacroCat(scan.type ?? 'other', 'Category', LucideIcons.fingerprint, Colors.blue),
                      Container(width: 1, height: 32, color: AppColors.border),
                      _buildQuickMacroCat(scan.details ?? 'Unknown', 'Details', LucideIcons.checkCircle, Colors.green),
                      Container(width: 1, height: 32, color: AppColors.border),
                      _buildQuickMacroCat('${(scan.confidence * 100).round()}%', 'Confidence', LucideIcons.flame, Colors.orange),
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
                      label: const Text('Edit foods & portions'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        side: const BorderSide(color: AppColors.borderDark),
                      ),
                    ),
                  ),

                if (isFood && scan.items.isNotEmpty) ...[
                  _buildFoodsCard(scan),
                  const SizedBox(height: 24),
                ],
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
                          'This meal is ${scan.protein > 20 ? 'excellent for muscle recovery due to its high protein content' : 'a balanced choice for your daily intake'}. '
                          '${scan.calories > 800 ? ' It is quite calorie-dense, so consider balancing your next meal with lighter options.' : ' It fits perfectly within your daily calorie budget.'}',
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
                          child: Text('"${scan.description}"', style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary, height: 1.5)),
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

  Widget _buildFoodsCard(ScanResult scan) {
    String amount(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scan.items.length == 1 ? 'FOOD' : 'FOODS IN THIS MEAL',
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < scan.items.length; i++) ...[
            if (i > 0) const Divider(height: 20, color: AppColors.border),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(scan.items[i].name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        scan.items[i].source == 'manual' && scan.items[i].servingUnit == 'serving'
                            ? 'P ${amount(scan.items[i].protein)} · C ${amount(scan.items[i].carbs)} · F ${amount(scan.items[i].fats)} g'
                            : '${amount(scan.items[i].estimatedWeight)} ${scan.items[i].servingUnit}  ·  P ${amount(scan.items[i].protein)} · C ${amount(scan.items[i].carbs)} · F ${amount(scan.items[i].fats)} g',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text('${scan.items[i].calories.round()} kcal',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
              ],
            ),
          ],
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
    final limitCals = profile.calorieLimit ?? 2000;
    final isOver = dailyCals > limitCals;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: isOver ? Colors.red.shade50.withValues(alpha: 0.3) : Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: isOver ? Colors.red.shade200 : AppColors.border)),
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
          _buildImpactRow('Protein', scan.protein, dailySummary?.totalProtein ?? 0, profile.proteinGoal ?? 0, Colors.blue),
          const SizedBox(height: 16),
          _buildImpactRow('Carbs', scan.carbs, dailySummary?.totalCarbs ?? 0, profile.carbsGoal ?? 0, Colors.orange),
          const SizedBox(height: 16),
          _buildImpactRow('Fats', scan.fats, dailySummary?.totalFats ?? 0, profile.fatsGoal ?? 0, Colors.purple),
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
                Text('${(percTotal * 100).round()}% of goal', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: (percTotal >= 1.0) ? Colors.blue.shade600 : Colors.green.shade600)),
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
