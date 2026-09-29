import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/models/scan_result.dart';
import '../../../app.dart' show retentionNoticeProvider;
import '../../../core/ai/ai_models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/image_preprocessor.dart';
import '../../scan/screens/scan_review_screen.dart';
import '../../../core/widgets/ai_model_card.dart';
import '../../../core/widgets/scan_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/animated_entry.dart';
import '../../auth/providers/user_provider.dart';
import '../widgets/calorie_progress_ring.dart';
import '../widgets/healthy_food_suggestions.dart';
import '../widgets/meal_reminders_sheet.dart';
import '../widgets/module_shortcuts.dart';
import '../widgets/today_activity_card.dart';
import '../widgets/top_insight_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  /// Entry point for the scan button: make sure the AI is available, pick a
  /// photo source, then analyse.
  Future<void> _startScan() async {
    if (_isProcessing) return;

    if (!ref.read(gemmaModelProvider).isInstalled) {
      await showAiModelSheet(context);
      if (!mounted || !ref.read(gemmaModelProvider).isInstalled) return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.camera),
                title: const Text('Take a photo', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(LucideIcons.image),
                title: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    await _handleImageCapture(source);
  }

  Future<void> _handleImageCapture(ImageSource source) async {
    XFile? image;
    try {
      image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open the camera or gallery. Check app permissions.')));
      }
      return;
    }
    if (image == null || !mounted) return;

    setState(() => _isProcessing = true);
    String? outcome;
    try {
      final bytes = await image.readAsBytes();

      // Understand the photo on-device. Nothing is saved yet: the user reviews
      // and confirms the result on the next screen.
      final ai = ref.read(nutritionAiProvider);
      final analysis = await ref.read(foodTwinServiceProvider).personalize(await ai.analyzeMeal(bytes));
      final prepared = await ImagePreprocessor.prepare(bytes);

      if (!mounted) return;
      setState(() => _isProcessing = false);
      outcome = await context.push<String>(
        AppRoutes.scanReview,
        extra: ScanReviewArgs.newMeal(analysis: analysis, imageBytes: prepared),
      );
    } on AiException catch (e) {
      if (mounted) await _showScanFailure(e);
    } catch (e) {
      debugPrint('[Home] scan failed: $e');
      if (mounted) {
        await _showScanFailure(AiException('Something went wrong analysing this photo. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }

    if (outcome == kRetakeResult && mounted) await _startScan();
  }

  Future<void> _showScanFailure(AiException e) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Couldn't analyse that photo"),
        content: Text(e.message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'close'), child: const Text('Close')),
          if (e.needsModel)
            TextButton(onPressed: () => Navigator.pop(ctx, 'model'), child: const Text('Get AI model'))
          else
            TextButton(onPressed: () => Navigator.pop(ctx, 'manual'), child: const Text('Log manually')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'manual') _showManualLogModal();
    if (choice == 'model') await showAiModelSheet(context);
  }

  Future<void> _handleAddWater(int amount) async {
    await ref.read(summaryRepositoryProvider).addWater(amount);
  }

  void _showSearchModal() => context.push(AppRoutes.foodLibrary);

  void _showManualLogModal() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Manual Log Modal',
      pageBuilder: (context, anim1, anim2) => _ManualLogModal(
        onLogSubmit: (res) => _logManual(res, isSearchModal: false),
      ),
    );
  }

  Future<void> _logManual(ScanResult partialData, {required bool isSearchModal, bool shouldPop = true}) async {
    if (isSearchModal) Navigator.of(context).pop();

    setState(() => _isProcessing = true);
    try {
      final saved = await ref.read(scanRepositoryProvider).add(
            partialData.copyWith(confidence: 1.0, timestamp: DateTime.now().toIso8601String()),
          );
      if (mounted) {
        if (shouldPop && !isSearchModal) Navigator.of(context).pop();
        context.push('${AppRoutes.result}/${saved.id}', extra: saved);
      }
    } catch (e) {
      debugPrint('[Home] manual log failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save this meal.')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(userNotifierProvider);
    final profile = userState.profile;
    final dailySummarySync = ref.watch(dailySummaryStreamProvider).valueOrNull;
    final scansSync = ref.watch(scanHistoryStreamProvider).valueOrNull ?? [];

    final calorieLimit = profile?.calorieLimit ?? 0;
    final calorieProgress =
        calorieLimit > 0 ? (dailySummarySync?.totalCalories ?? 0) / calorieLimit : 0.0;
        
    final waterGoal = (profile?.waterGoal ?? 0) > 0 ? profile!.waterGoal! : 2500;
    final waterProgress = (dailySummarySync?.totalWater ?? 0) / waterGoal;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                const _RetentionNoticeBanner(),
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Hi, ', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                            Text((profile?.displayName?.split(' ') ?? ['User']).first, 
                                 style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.primary)),
                          ],
                        ),
                        const Text('Your health journey continues.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textTertiary)),
                      ],
                    ),
                    Row(
                      children: [
                        InkWell(
                          onTap: _showSearchModal,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)),
                            child: const Icon(LucideIcons.search, color: AppColors.textTertiary, size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        InkWell(
                          onTap: () => context.push(AppRoutes.settings),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)),
                            clipBehavior: Clip.hardEdge,
                            child: (profile?.photoURL != null && profile!.photoURL!.isNotEmpty)
                              ? ScanImage(path: profile.photoURL, cacheWidth: 160)
                              : const Icon(LucideIcons.user, color: AppColors.textTertiary, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // The one insight worth acting on right now
                const TopInsightCard(),

                // Daily Progress Ring & Macro Overview
                AnimatedFadeSlide(
                  delay: const Duration(milliseconds: 100),
                  child: CalorieProgressRing(
                    dailySummary: dailySummarySync,
                    profile: profile,
                    progress: calorieProgress,
                  ),
                ),
                
                const SizedBox(height: 24),

                // Recurring Daily Meal Reminders Card
                const AnimatedFadeSlide(
                  delay: const Duration(milliseconds: 150),
                  child: MealRemindersCard(),
                ),

                const SizedBox(height: 24),

                // Water Tracker
                AnimatedFadeSlide(
                  delay: const Duration(milliseconds: 200),
                  child: _buildWaterCard(dailySummarySync, profile, waterProgress),
                ),

                const SizedBox(height: 24),
                // Today's movement (steps, active energy)
                const AnimatedFadeSlide(
                  delay: Duration(milliseconds: 230),
                  child: TodayActivityCard(),
                ),

                const SizedBox(height: 24),

                const ModuleShortcuts(),

                const SizedBox(height: 24),

                // Quick Actions
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _startScan,
                        borderRadius: BorderRadius.circular(32),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
                                child: const Icon(LucideIcons.camera, color: Colors.white),
                              ),
                              const SizedBox(height: 16),
                              const Text('Scan Meal', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              const Text('POWERED BY GEMINI 3.1 PRO', style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: _showManualLogModal,
                        borderRadius: BorderRadius.circular(32),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
                                child: Icon(LucideIcons.plus, color: Colors.blue.shade600),
                              ),
                              const SizedBox(height: 16),
                              const Text('Manual Log', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              const Text('INPUT DETAILS', style: TextStyle(color: AppColors.textTertiary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // AI Coach Link
                InkWell(
                  onTap: () => context.go(AppRoutes.coach),
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16)),
                          child: Icon(LucideIcons.sparkles, color: Colors.green.shade600),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('AI Health Coach', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                              SizedBox(height: 2),
                              Text('PERSONALIZED ADVICE & INSIGHTS', style: TextStyle(color: AppColors.textTertiary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                            ],
                          ),
                        ),
                        const Icon(LucideIcons.chevronRight, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Suggested Healthy Food Options Section
                AnimatedFadeSlide(
                  delay: const Duration(milliseconds: 250),
                  child: HealthyFoodSuggestions(
                    dailySummary: dailySummarySync,
                    profile: profile,
                    onQuickLog: (scan) => _logManual(scan, isSearchModal: false, shouldPop: false),
                  ),
                ),

                const SizedBox(height: 24),

                // Last Scan Preview
                if (scansSync.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('LAST SCAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
                      InkWell(
                        onTap: () => context.push(AppRoutes.history),
                        child: const Row(
                          children: [
                            Text('History', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                            Icon(LucideIcons.chevronRight, size: 14, color: AppColors.primary),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => context.push('/result/${scansSync.first.id}'),
                    borderRadius: BorderRadius.circular(32),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
                            clipBehavior: Clip.hardEdge,
                            child: ScanImage(path: scansSync.first.imageUrl, cacheWidth: 400),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(scansSync.first.foodName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade100)),
                                      child: Text('${scansSync.first.calories} kcal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 40, height: 40,
                            decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
                            child: const Icon(LucideIcons.chevronRight, color: AppColors.textTertiary, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Processing Overlay identical directly mapped from React AnimatePresence wrapper
        if (_isProcessing)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.white.withValues(alpha: 0.8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 96, height: 96,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 40)]),
                      child: const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3)),
                    ).animate().scale(delay: 100.ms).fadeIn(),
                    const SizedBox(height: 32),
                    const Text('AI is Analyzing', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 12),
                    const Text('Identifying ingredients and estimating nutrition on your device.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary)).animate().fadeIn(delay: 300.ms),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(duration: 200.ms),
      ],
    );
  }

  Widget _buildWaterCard(dailySummarySync, profile, double progress) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
                    child: Icon(LucideIcons.droplets, color: Colors.blue.shade500, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Hydration', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const Text('DAILY WATER INTAKE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
                    ],
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${dailySummarySync?.totalWater ?? 0}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -1)),
                  Text(' / ${profile?.waterGoal ?? 2500}ml', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.blue.shade50.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Simplified Wave Fill mapped natively using continuous sizing constraints
                AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  height: 160 * progress.clamp(0.0, 1.0),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.blue.shade400, Colors.blue.shade600]),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(progress * 100).round()}%', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: progress > 0.45 ? Colors.white : Colors.blue.shade600, letterSpacing: -2.0)),
                      Text('DAILY GOAL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2.0, color: progress > 0.45 ? Colors.white70 : Colors.blue.shade400)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _handleAddWater(250),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderDark)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.plus, size: 14, color: Colors.blue.shade600),
                        const SizedBox(width: 8),
                        Text('250ml', style: TextStyle(color: Colors.blue.shade600, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => _handleAddWater(500),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderDark)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.plus, size: 14, color: Colors.blue.shade600),
                        const SizedBox(width: 8),
                        Text('500ml', style: TextStyle(color: Colors.blue.shade600, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// MODALS
// ---------------------------------------------------------

class _ManualLogModal extends StatefulWidget {
  final Function(ScanResult) onLogSubmit;
  const _ManualLogModal({required this.onLogSubmit});

  @override
  State<_ManualLogModal> createState() => _ManualLogModalState();
}

class _ManualLogModalState extends State<_ManualLogModal> {
  final _nameCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _proCtrl = TextEditingController();
  final _carbCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) return;
    
    final partialData = ScanResult(
      id: 'temp', userId: '', timestamp: '',
      foodName: _nameCtrl.text.trim(),
      type: 'food', confidence: 1.0, description: 'Added manually',
      calories: int.tryParse(_calCtrl.text) ?? 0,
      protein: int.tryParse(_proCtrl.text) ?? 0,
      carbs: int.tryParse(_carbCtrl.text) ?? 0,
      fats: int.tryParse(_fatCtrl.text) ?? 0,
    );
    
    widget.onLogSubmit(partialData);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
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
                        const Text('Manual Log', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
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
                    SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: _submit, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))), child: const Text('Log Meal', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))),
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


/// One-time notice after old history was archived and removed.
class _RetentionNoticeBanner extends ConsumerWidget {
  const _RetentionNoticeBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(retentionNoticeProvider);
    if (report == null) return const SizedBox.shrink();

    final failed = report.failed;
    final text = failed
        ? 'We could not archive your older history, so nothing was deleted.'
        : 'Archived ${report.scans} older meals and removed them from this device. '
            'You can find the archive in Settings > Data & privacy.';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: failed ? Colors.red.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(failed ? LucideIcons.alertTriangle : LucideIcons.archive,
              size: 18, color: failed ? Colors.red.shade600 : Colors.blue.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: failed ? Colors.red.shade800 : Colors.blue.shade800)),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 16),
            onPressed: () => ref.read(retentionNoticeProvider.notifier).state = null,
          ),
        ],
      ),
    );
  }
}
