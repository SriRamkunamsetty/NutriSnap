import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/firebase_exception_handler.dart';
import '../../../core/widgets/animated_entry.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../auth/providers/user_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 1;
  bool _isSaving = false;
  final int _totalSteps = 5;

  late TextEditingController _nameController;
  int _height = 175;
  int _weight = 70;
  Goal _goal = Goal.maintain;
  int _calorieLimit = 2000;
  int _proteinGoal = 150;
  int _carbsGoal = 250;
  int _fatsGoal = 70;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userNotifierProvider).profile;
    
    _nameController = TextEditingController(text: profile?.displayName ?? '');
    _height = profile?.height ?? 175;
    _weight = profile?.weight ?? 70;
    _goal = profile?.goal ?? Goal.maintain;
    _calorieLimit = profile?.calorieLimit ?? 2000;
    _proteinGoal = profile?.proteinGoal ?? 150;
    _carbsGoal = profile?.carbsGoal ?? 250;
    _fatsGoal = profile?.fatsGoal ?? 70;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _handleNext() {
    if (_step < _totalSteps) {
      if (_step == 1 && _nameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your name.')));
        return;
      }
      setState(() => _step++);
    } else {
      _handleComplete();
    }
  }

  void _handleBack() {
    if (_step > 1) {
      setState(() => _step--);
    }
  }

  Future<void> _handleComplete() async {
    setState(() => _isSaving = true);
    
    try {
      final heightInMeters = _height / 100;
      final bmi = _weight / (heightInMeters * heightInMeters);
      final roundedBmi = double.parse(bmi.toStringAsFixed(1));

      final profilePath = UserProfile(
        uid: ref.read(userNotifierProvider).authUser!.uid,
        displayName: _nameController.text.trim(),
        height: _height,
        weight: _weight,
        bmi: roundedBmi,
        goal: _goal,
        calorieLimit: _calorieLimit,
        proteinGoal: _proteinGoal,
        carbsGoal: _carbsGoal,
        fatsGoal: _fatsGoal,
        hasCompletedOnboarding: true,
      );

      final storage = ref.read(storageServiceProvider);
      await storage.saveUserProfile(profilePath);

      // Force Riverpod to update so Router catches the new logic natively
      await ref.read(userNotifierProvider.notifier).refreshProfile();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(FirebaseExceptionHandler.handleException(e, 'Onboarding'))));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _updateSuggestedMacros(Goal newGoal, int calories) {
    int p = 150;
    int c = 250;
    int f = 70;

    if (newGoal == Goal.lose) {
      p = (_weight * 2.2).round();
      f = ((calories * 0.25) / 9).round();
      c = ((calories - (p * 4) - (f * 9)) / 4).round();
    } else if (newGoal == Goal.gain) {
      p = (_weight * 2).round();
      f = ((calories * 0.25) / 9).round();
      c = ((calories - (p * 4) - (f * 9)) / 4).round();
    } else {
      p = (_weight * 1.8).round();
      f = ((calories * 0.3) / 9).round();
      c = ((calories - (p * 4) - (f * 9)) / 4).round();
    }

    setState(() {
      _proteinGoal = p;
      _carbsGoal = c;
      _fatsGoal = f;
    });
  }

  void _updateSuggestedCalories(Goal newGoal) {
    int base = 2000;
    if (newGoal == Goal.lose) base = 1700;
    if (newGoal == Goal.gain) base = 2500;
    setState(() => _calorieLimit = base);
    _updateSuggestedMacros(newGoal, base);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Progress Bar
              Row(
                children: List.generate(_totalSteps, (i) {
                  return Expanded(
                    child: Container(
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: i + 1 <= _step ? AppColors.primary : AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),

              // Dynamic Step View
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: _buildStepContent(),
                ),
              ),

              // Navigation Buttons
              const SizedBox(height: 24),
              Row(
                children: [
                  if (_step > 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: InkWell(
                        onTap: _handleBack,
                        borderRadius: BorderRadius.circular(32),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(LucideIcons.chevronLeft, color: AppColors.textTertiary),
                        ),
                      ),
                    ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _handleNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                      ),
                      child: _isSaving
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_step == _totalSteps ? 'Complete Profile' : 'Continue', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                              const SizedBox(width: 8),
                              const Icon(LucideIcons.chevronRight, size: 20),
                            ],
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 1: return _buildStep1(key: const ValueKey(1));
      case 2: return _buildStep2(key: const ValueKey(2));
      case 3: return _buildStep3(key: const ValueKey(3));
      case 4: return _buildStep4(key: const ValueKey(4));
      case 5: return _buildStep5(key: const ValueKey(5));
      default: return const SizedBox.shrink(key: ValueKey('empty'));
    }
  }

  Widget _buildStepHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
        const SizedBox(height: 32),
      ],
    );
  }

  // STEP 1: NAME
  Widget _buildStep1({required Key key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('What should we call you?', "This is how you'll appear in your health dashboard."),
        AppTextField(
          controller: _nameController,
          hintText: 'Your Name',
          icon: LucideIcons.user,
        ),
      ],
    );
  }

  // STEP 2: BODY STATS
  Widget _buildStep2({required Key key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Your Body Stats', 'We use these to calculate your BMI and nutritional needs.'),
        
        const Padding(
          padding: EdgeInsets.only(left: 16, bottom: 8),
          child: Text('HEIGHT (CM)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
        ),
        TextFormField(
          initialValue: _height.toString(),
          keyboardType: TextInputType.number,
          onChanged: (val) => _height = int.tryParse(val) ?? 175,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            prefixIcon: const Icon(LucideIcons.ruler, color: AppColors.textTertiary),
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          ),
        ),
        
        const SizedBox(height: 24),

        const Padding(
          padding: EdgeInsets.only(left: 16, bottom: 8),
          child: Text('WEIGHT (KG)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
        ),
        TextFormField(
          initialValue: _weight.toString(),
          keyboardType: TextInputType.number,
          onChanged: (val) => _weight = int.tryParse(val) ?? 70,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            prefixIcon: const Icon(LucideIcons.weight, color: AppColors.textTertiary),
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  // STEP 3: GOALS
  Widget _buildStep3({required Key key}) {
    final goalsList = [
      {'id': Goal.lose, 'label': 'Lose Weight', 'desc': 'Burn fat and get leaner', 'icon': LucideIcons.zap, 'color': Colors.orange},
      {'id': Goal.maintain, 'label': 'Maintain', 'desc': 'Stay healthy and balanced', 'icon': LucideIcons.target, 'color': Colors.green},
      {'id': Goal.gain, 'label': 'Build Muscle', 'desc': 'Gain strength and mass', 'icon': LucideIcons.weight, 'color': Colors.blue},
    ];

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader("What's your goal?", 'Choose the path that fits your current health journey.'),
        Expanded(
          child: ListView.separated(
            itemCount: goalsList.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = goalsList[index];
              final isSelected = _goal == item['id'];
              final color = item['color'] as MaterialColor;
              
              return InkWell(
                onTap: () {
                  setState(() => _goal = item['id'] as Goal);
                  _updateSuggestedCalories(_goal);
                },
                borderRadius: BorderRadius.circular(32),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isSelected ? color.shade50.withOpacity(0.5) : Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: isSelected ? color.shade500 : Colors.white, width: 2),
                    boxShadow: [if (isSelected) BoxShadow(color: color.shade100, blurRadius: 10, spreadRadius: 1)],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(16)),
                        child: Icon(item['icon'] as IconData, color: color.shade500, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['label'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                            Text(item['desc'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Container(
                          width: 32, height: 32,
                          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          child: const Icon(LucideIcons.check, color: Colors.white, size: 16),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // STEP 4: CALORIE TARGET
  Widget _buildStep4({required Key key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Daily Calorie Target', 'Based on your goal, we suggest this daily limit.'),
        AppCard(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              const Text('SUGGESTED LIMIT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 2.0)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IntrinsicWidth(
                    child: TextField(
                      controller: TextEditingController(text: _calorieLimit.toString())..selection = TextSelection.collapsed(offset: _calorieLimit.toString().length),
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null) {
                          _calorieLimit = parsed;
                          _updateSuggestedMacros(_goal, parsed);
                        }
                      },
                      style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -2.0),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero, fillColor: Colors.transparent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('kcal', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.borderDark)),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                height: 8,
                width: double.infinity,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
                child: Row(
                  children: [
                    Expanded(child: AnimatedContainer(duration: const Duration(milliseconds: 500), color: AppColors.primary, curve: Curves.easeOut)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'You can always adjust this later in your settings. This is just a starting point for your journey.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textTertiary, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // STEP 5: MACROS
  Widget _buildStep5({required Key key}) {
    final macros = [
      {'label': 'Protein', 'value': _proteinGoal, 'setter': (val) => _proteinGoal = val, 'color': Colors.blue, 'icon': LucideIcons.zap},
      {'label': 'Carbs', 'value': _carbsGoal, 'setter': (val) => _carbsGoal = val, 'color': Colors.orange, 'icon': LucideIcons.zap},
      {'label': 'Fats', 'value': _fatsGoal, 'setter': (val) => _fatsGoal = val, 'color': Colors.purple, 'icon': LucideIcons.zap},
    ];

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Macronutrient Goals', "We've calculated these based on your calorie target."),
        Expanded(
          child: ListView.separated(
            itemCount: macros.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final item = macros[index];
              final color = item['color'] as MaterialColor;
              
              return AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(16)),
                      child: Icon(item['icon'] as IconData, color: color.shade500, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Text(item['label'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                    const Spacer(),
                    IntrinsicWidth(
                      child: TextField(
                        controller: TextEditingController(text: item['value'].toString())..selection = TextSelection.collapsed(offset: item['value'].toString().length),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null) {
                            setState(() => (item['setter'] as Function(int))(parsed));
                          }
                        },
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero, fillColor: Colors.transparent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('g', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.borderDark)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
