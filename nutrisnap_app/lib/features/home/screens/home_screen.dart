import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/models/scan_result.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/animated_entry.dart';
import '../../auth/providers/user_provider.dart';

// Standalone Mock Database port matching the React code logic.
const Map<String, Map<String, dynamic>> _foodDatabase = {
  'pizza': {'foodName': 'Pizza Slice', 'calories': 285, 'protein': 12, 'carbs': 36, 'fats': 10, 'type': 'food', 'confidence': 0.8},
  'burger': {'foodName': 'Classic Burger', 'calories': 550, 'protein': 25, 'carbs': 45, 'fats': 30, 'type': 'food', 'confidence': 0.8},
  'salad': {'foodName': 'Garden Salad', 'calories': 150, 'protein': 5, 'carbs': 10, 'fats': 8, 'type': 'food', 'confidence': 0.8},
  'apple': {'foodName': 'Red Apple', 'calories': 95, 'protein': 0.5, 'carbs': 25, 'fats': 0.3, 'type': 'food', 'confidence': 0.9},
  'chicken': {'foodName': 'Grilled Chicken', 'calories': 330, 'protein': 50, 'carbs': 0, 'fats': 12, 'type': 'food', 'confidence': 0.85},
};

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _handleImageCapture() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery, 
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image == null) return;

    setState(() => _isProcessing = true);

    try {
      final file = File(image.path);
      final storage = ref.read(storageServiceProvider);
      final gemini = ref.read(geminiServiceProvider);
      
      // 1. Upload to storage 
      final imageUrl = await storage.uploadScanImage(file);
      
      // 2. Fetch bytes
      final bytes = await file.readAsBytes();
      
      // 3. Analyze locally
      ScanResult? result;
      try {
        result = await gemini.analyzeFoodImage(bytes, 'image/jpeg');
      } catch (e) {
        debugPrint('AI Analysis failed, falling back...');
        // Fake local fallback
        final lowerPath = image.path.toLowerCase();
        final match = _foodDatabase.keys.where((k) => lowerPath.contains(k)).firstOrNull;
        
        if (match != null) {
          result = ScanResult.fromMap({..._foodDatabase[match]!, 'id': 'temp'});
        } else {
          result = const ScanResult(
            id: 'temp', userId: '', timestamp: '',
            foodName: 'Unknown Meal',
            type: 'food',
            calories: 450, protein: 15, carbs: 40, fats: 20, confidence: 0.5,
            description: "We couldn't reach the AI, so we provided a standard estimation.",
          );
        }
      }
      
      if (result != null && result.foodName.isNotEmpty) {
         final finalScan = result.copyWith(imageUrl: imageUrl, confidence: result.confidence > 0 ? result.confidence : 1.0);
         final savedScan = await storage.saveScanResult(finalScan);

         if (savedScan != null && mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan saved successfully!')));
           // Navigate mapped to results
           context.push('/result/${savedScan.id}');
         }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to process image: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleAddWater(int amount) async {
    await ref.read(storageServiceProvider).updateWaterIntake(amount);
  }

  void _showSearchModal() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Search Modal',
      pageBuilder: (context, anim1, anim2) => _SearchModal(
        onResultSelect: (res) => _logManual(res, isSearchModal: true),
      ),
    );
  }

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

  Future<void> _logManual(ScanResult partialData, {required bool isSearchModal}) async {
    if (isSearchModal) Navigator.of(context).pop();
    
    setState(() => _isProcessing = true);
    try {
      final storage = ref.read(storageServiceProvider);
      final finalScan = partialData.copyWith(
        imageUrl: 'https://picsum.photos/seed/food/200/200', // React fallback logic constraint
        confidence: 1.0,
      );

      final saved = await storage.saveScanResult(finalScan);
      if (saved != null && mounted) {
        if (!isSearchModal) Navigator.of(context).pop();
        context.push('/result/${saved.id}');
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

    final calorieProgress = (profile?.calorieLimit != null && profile!.calorieLimit > 0)
        ? (dailySummarySync?.totalCalories ?? 0) / profile.calorieLimit
        : 0.0;
        
    final waterProgress = (profile?.waterGoal != null && profile!.waterGoal > 0)
        ? (dailySummarySync?.totalWater ?? 0) / profile.waterGoal
        : (dailySummarySync?.totalWater ?? 0) / 2500;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
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
                              ? CachedNetworkImage(imageUrl: profile.photoURL!, fit: BoxFit.cover)
                              : const Icon(LucideIcons.user, color: AppColors.textTertiary, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Daily Progress Card (Calorie fuel)
                AnimatedFadeSlide(
                  delay: const Duration(milliseconds: 100),
                  child: _buildCalorieCard(dailySummarySync, profile, calorieProgress),
                ),
                
                const SizedBox(height: 24),

                // Water Tracker
                AnimatedFadeSlide(
                  delay: const Duration(milliseconds: 200),
                  child: _buildWaterCard(dailySummarySync, profile, waterProgress),
                ),

                const SizedBox(height: 24),

                // Quick Actions
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _handleImageCapture,
                        borderRadius: BorderRadius.circular(32),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
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
                  onTap: () => context.push(AppRoutes.chat),
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
                    onTap: () => context.push('/result/\${scansSync.first.id}'),
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
                            child: CachedNetworkImage(imageUrl: scansSync.first.imageUrl ?? '', fit: BoxFit.cover, errorWidget: (c,u,e) => const Icon(LucideIcons.camera)),
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
                                      child: Text('\${scansSync.first.calories} kcal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
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
                color: Colors.white.withOpacity(0.8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 96, height: 96,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 40)]),
                      child: const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3)),
                    ).animate().scale(delay: 100.ms).fadeIn(),
                    const SizedBox(height: 32),
                    const Text('AI is Analyzing', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 12),
                    const Text('Identifying ingredients and calculating\nnutrition for your meal.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary)).animate().fadeIn(delay: 300.ms),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(duration: 200.ms),
      ],
    );
  }

  Widget _buildCalorieCard(dailySummarySync, profile, double progress) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle))
                      .animate(onPlay: (controller) => controller.repeat(reverse: true)).fadeOut(duration: 1.seconds),
                  const SizedBox(width: 8),
                  const Text('DAILY FUEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.shade100)),
                child: Text('\${(progress * 100).round()}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.green.shade600)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('\${dailySummarySync?.totalCalories ?? 0}', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -2)),
              const SizedBox(width: 8),
              Text('/ \${profile?.calorieLimit ?? 2000} kcal', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            height: 12,
            width: double.infinity,
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(6)),
            child: Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeOut,
                    color: progress > 1 ? Colors.red : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMacroInfo('Protein', dailySummarySync?.totalProtein ?? 0, Colors.blue),
              _buildMacroInfo('Carbs', dailySummarySync?.totalCarbs ?? 0, Colors.orange),
              _buildMacroInfo('Fats', dailySummarySync?.totalFats ?? 0, Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroInfo(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('\$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const Text('g', style: TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.bold)),
          ],
        )
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
                  Text('\${dailySummarySync?.totalWater ?? 0}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -1)),
                  Text(' / \${profile?.waterGoal ?? 2500}ml', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.blue.shade50.withOpacity(0.5), borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.white.withOpacity(0.2))),
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
                      Text('\${(progress * 100).round()}%', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: progress > 0.45 ? Colors.white : Colors.blue.shade600, letterSpacing: -2.0)),
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

class _SearchModal extends StatefulWidget {
  final Function(ScanResult) onResultSelect;
  const _SearchModal({required this.onResultSelect});

  @override
  State<_SearchModal> createState() => _SearchModalState();
}

class _SearchModalState extends State<_SearchModal> {
  String _query = '';
  List<Map<String, dynamic>> _results = [];

  void _search(String q) {
    setState(() {
      _query = q;
      if (q.trim().isEmpty) {
        _results = [];
      } else {
        _results = _foodDatabase.values
            .where((data) => (data['foodName'] as String).toLowerCase().contains(q.toLowerCase()))
            .toList();
      }
    });
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
              onTap: () {}, // Prevent dismissal when tapping inside
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.search, color: AppColors.textTertiary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              autofocus: true,
                              onChanged: _search,
                              decoration: const InputDecoration(border: InputBorder.none, hintText: 'Search for food (e.g. pizza)'),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(LucideIcons.x, color: AppColors.textTertiary, size: 20),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 300,
                      child: _results.isEmpty 
                        ? Center(child: Text(_query.isEmpty ? 'Try searching for common foods' : 'No results found', style: const TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.bold)))
                        : ListView.separated(
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final item = _results[i];
                              return InkWell(
                                onTap: () {
                                  widget.onResultSelect(ScanResult.fromMap({...item, 'id': 'temp'}));
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(16)),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item['foodName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          Text('\${item['calories']} kcal • P: \${item['protein']}g • C: \${item['carbs']}g', style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                                        ],
                                      ),
                                      const Icon(LucideIcons.plus, color: AppColors.textTertiary),
                                    ],
                                  ),
                                ),
                              );
                            },
                        ),
                    ),
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
