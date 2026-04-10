import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../services/firebase_service.dart';
import '../models/user_profile.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isSaving = false;

  // Form State
  String _name = '';
  double _height = 175;
  double _weight = 70;
  String _goal = 'maintain';
  int _calorieLimit = 2000;
  int _proteinGoal = 150;
  int _carbsGoal = 250;
  int _fatsGoal = 70;

  final int _totalSteps = 5;

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutQuart,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutQuart,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() => _isSaving = true);
    final userProvider = context.read<UserProvider>();
    final firebaseService = FirebaseService();

    try {
      final heightInMeters = _height / 100;
      final bmi = _weight / (heightInMeters * heightInMeters);

      final profile = UserProfile(
        uid: firebaseService.currentUserId!,
        email: userProvider.profile?.email ?? '',
        displayName: _name,
        height: _height,
        weight: _weight,
        bmi: bmi,
        goal: _goal,
        calorieLimit: _calorieLimit,
        waterGoal: 2500,
        proteinGoal: _proteinGoal,
        carbsGoal: _carbsGoal,
        fatsGoal: _fatsGoal,
      );

      await firebaseService.updateUserProfile(profile);
      // In a real app, we'd update a 'hasCompletedOnboarding' flag in Firestore
      // For this demo, we'll just navigate
      if (mounted) Navigator.pushReplacementNamed(context, '/');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              // Progress Bar
              Row(
                children: List.generate(_totalSteps, (index) {
                  return Expanded(
                    child: Container(
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: index <= _currentStep
                            ? const Color(0xFF10B981)
                            : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ).animate(target: index <= _currentStep ? 1 : 0).tint(color: const Color(0xFF10B981)),
                  );
                }),
              ),
              const SizedBox(height: 48),

              // Steps
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) => setState(() => _currentStep = index),
                  children: [
                    _buildStep1(),
                    _buildStep2(),
                    _buildStep3(),
                    _buildStep4(),
                    _buildStep5(),
                  ],
                ),
              ),

              // Navigation
              Row(
                children: [
                  if (_currentStep > 0)
                    GestureDetector(
                      onTap: _prevStep,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(LucideIcons.chevronLeft, color: Colors.grey),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isSaving ? null : _nextStep,
                      child: Container(
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _isSaving
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _currentStep == _totalSteps - 1
                                          ? 'Complete Profile'
                                          : 'Continue',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(LucideIcons.chevronRight, color: Colors.white),
                                  ],
                                ),
                        ),
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

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What should we call you?',
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0F172A),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'This is how you\'ll appear in your health dashboard.',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 48),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: TextField(
            onChanged: (val) => setState(() => _name = val),
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Your Name',
              border: InputBorder.none,
              icon: Icon(LucideIcons.user, color: Colors.grey),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms).moveX(begin: 20, end: 0);
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Body Stats',
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0F172A),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We use these to calculate your BMI and nutritional needs.',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 48),
        _buildStatInput('Height (cm)', _height, (val) => setState(() => _height = val), LucideIcons.ruler),
        const SizedBox(height: 24),
        _buildStatInput('Weight (kg)', _weight, (val) => setState(() => _weight = val), LucideIcons.weight),
      ],
    ).animate().fadeIn(duration: 500.ms).moveX(begin: 20, end: 0);
  }

  Widget _buildStatInput(String label, double value, Function(double) onChanged, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: TextField(
            keyboardType: TextInputType.number,
            onChanged: (val) => onChanged(double.tryParse(val) ?? value),
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: value.toString(),
              border: InputBorder.none,
              icon: Icon(icon, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What\'s your goal?',
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0F172A),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Choose the path that fits your current health journey.',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 48),
        _buildGoalOption('lose', 'Lose Weight', 'Burn fat and get leaner', LucideIcons.zap, Colors.orange),
        const SizedBox(height: 16),
        _buildGoalOption('maintain', 'Maintain', 'Stay healthy and balanced', LucideIcons.target, Colors.green),
        const SizedBox(height: 16),
        _buildGoalOption('gain', 'Build Muscle', 'Gain strength and mass', LucideIcons.dumbbell, Colors.blue),
      ],
    ).animate().fadeIn(duration: 500.ms).moveX(begin: 20, end: 0);
  }

  Widget _buildGoalOption(String id, String label, String desc, IconData icon, Color color) {
    final isSelected = _goal == id;
    return GestureDetector(
      onTap: () => setState(() {
        _goal = id;
        if (id == 'lose') _calorieLimit = 1700;
        else if (id == 'gain') _calorieLimit = 2500;
        else _calorieLimit = 2000;
      }),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    desc,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(LucideIcons.checkCircle, color: Color(0xFF10B981)),
          ],
        ),
      ),
    );
  }

  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Calorie Target',
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0F172A),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Based on your goal, we suggest this daily limit.',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 48),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(48),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                'SUGGESTED LIMIT',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (val) => setState(() => _calorieLimit = int.tryParse(val) ?? _calorieLimit),
                      style: GoogleFonts.outfit(
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -2,
                      ),
                      decoration: InputDecoration(
                        hintText: _calorieLimit.toString(),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  Text(
                    'kcal',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: const LinearProgressIndicator(
                  value: 1.0,
                  minHeight: 8,
                  backgroundColor: Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'You can always adjust this later in your settings. This is just a starting point for your journey.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms).moveY(begin: 20, end: 0);
  }

  Widget _buildStep5() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Macronutrient Goals',
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0F172A),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We\'ve calculated these based on your calorie target.',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 48),
        _buildMacroInput('Protein', _proteinGoal, (val) => setState(() => _proteinGoal = val), Colors.blue),
        const SizedBox(height: 16),
        _buildMacroInput('Carbs', _carbsGoal, (val) => setState(() => _carbsGoal = val), Colors.orange),
        const SizedBox(height: 16),
        _buildMacroInput('Fats', _fatsGoal, (val) => setState(() => _fatsGoal = val), Colors.purple),
      ],
    ).animate().fadeIn(duration: 500.ms).moveX(begin: 20, end: 0);
  }

  Widget _buildMacroInput(String label, int value, Function(int) onChanged, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(LucideIcons.zap, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 60,
            child: TextField(
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              onChanged: (val) => onChanged(int.tryParse(val) ?? value),
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: value.toString(),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'g',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
