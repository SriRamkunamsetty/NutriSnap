import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../providers/user_provider.dart';
import '../services/gemini_service.dart';
import '../services/firebase_service.dart';
import '../models/scan_result.dart';
import '../models/user_profile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ImagePicker _picker = ImagePicker();
  final GeminiService _geminiService = GeminiService();
  final FirebaseService _firebaseService = FirebaseService();
  bool _isAnalyzing = false;
  bool _isEditing = false;
  bool _isSaving = false;

  late TextEditingController _heightController;
  late TextEditingController _weightController;
  late TextEditingController _calorieController;
  late TextEditingController _proteinController;
  late TextEditingController _carbsController;
  late TextEditingController _fatsController;
  String _selectedGoal = 'maintain';

  @override
  void initState() {
    super.initState();
    final profile = context.read<UserProvider>().profile;
    _heightController = TextEditingController(text: profile?.height.toString() ?? '175');
    _weightController = TextEditingController(text: profile?.weight.toString() ?? '70');
    _calorieController = TextEditingController(text: profile?.calorieLimit.toString() ?? '2000');
    _proteinController = TextEditingController(text: profile?.proteinGoal.toString() ?? '150');
    _carbsController = TextEditingController(text: profile?.carbsGoal.toString() ?? '250');
    _fatsController = TextEditingController(text: profile?.fatsGoal.toString() ?? '70');
    _selectedGoal = profile?.goal ?? 'maintain';
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      final userProvider = context.read<UserProvider>();
      final profile = userProvider.profile!;
      
      final updatedProfile = profile.copyWith(
        height: double.parse(_heightController.text),
        weight: double.parse(_weightController.text),
        calorieLimit: int.parse(_calorieController.text),
        proteinGoal: int.parse(_proteinController.text),
        carbsGoal: int.parse(_carbsController.text),
        fatsGoal: int.parse(_fatsController.text),
        goal: _selectedGoal,
        bmi: double.parse(_weightController.text) / 
             ((double.parse(_heightController.text) / 100) * (double.parse(_heightController.text) / 100)),
      );

      await _firebaseService.updateUserProfile(updatedProfile);
      setState(() => _isEditing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleBodyScan() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    setState(() => _isAnalyzing = true);

    try {
      final bytes = await image.readAsBytes();
      final mimeType = 'image/${image.path.split('.').last}';
      
      final result = await _geminiService.analyzeBody(bytes, mimeType);
      final imageUrl = await _firebaseService.uploadBodyImage(File(image.path));

      final userProvider = context.read<UserProvider>();
      final profile = userProvider.profile!;
      
      final updatedProfile = profile.copyWith(
        bodyType: result['bodyType'] ?? 'unknown',
        fatEstimate: (result['fatEstimate'] ?? 0).toDouble(),
      );

      await _firebaseService.updateUserProfile(updatedProfile);

      final scan = ScanResult(
        id: '',
        userId: profile.uid,
        foodName: 'Body Scan',
        type: 'person',
        description: 'Body Type: ${result['bodyType']}, Fat Estimate: ${result['fatEstimate']}%',
        calories: 0,
        protein: 0,
        carbs: 0,
        fats: 0,
        imageUrl: imageUrl,
        confidence: 1.0,
        timestamp: DateTime.now(),
      );

      await _firebaseService.addScan(scan);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Body scan successful!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Body scan failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final profile = userProvider.profile;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Settings',
                    style: GoogleFonts.outfit(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -1,
                    ),
                  ),
                  if (_isEditing)
                    TextButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(
                              'Save',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                    )
                  else
                    IconButton(
                      onPressed: () => setState(() => _isEditing = true),
                      icon: const Icon(LucideIcons.edit3, color: Color(0xFF10B981)),
                    ),
                ],
              ).animate().fadeIn().moveY(begin: 10, end: 0),
              const SizedBox(height: 32),

              // Profile Card
              Container(
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
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: profile?.photoURL != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.network(profile!.photoURL!, fit: BoxFit.cover),
                                )
                              : const Icon(LucideIcons.user, size: 32, color: Color(0xFF10B981)),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile?.displayName ?? 'User',
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                profile?.email ?? '',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat('BMI', profile?.bmi?.toStringAsFixed(1) ?? '--'),
                        _buildStat('Body Type', profile?.bodyType ?? '--'),
                        _buildStat('Fat %', profile?.fatEstimate != null ? '${profile!.fatEstimate}%' : '--'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _isAnalyzing ? null : _handleBodyScan,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _isAnalyzing 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)))
                              : const Icon(LucideIcons.sparkles, color: Color(0xFF10B981), size: 18),
                            const SizedBox(width: 12),
                            Text(
                              _isAnalyzing ? 'Analyzing Body...' : 'AI Body Scan',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 100.ms).moveY(begin: 10, end: 0),

              const SizedBox(height: 32),

              if (_isEditing) ...[
                _buildSectionTitle('EDIT PROFILE'),
                _buildEditField('Height (cm)', _heightController, LucideIcons.ruler),
                _buildEditField('Weight (kg)', _weightController, LucideIcons.scale),
                _buildEditField('Daily Calories', _calorieController, LucideIcons.flame),
                const SizedBox(height: 16),
                _buildGoalSelector(),
                const SizedBox(height: 24),
                _buildSectionTitle('MACRONUTRIENT GOALS'),
                _buildEditField('Protein (g)', _proteinController, LucideIcons.beef),
                _buildEditField('Carbs (g)', _carbsController, LucideIcons.wheat),
                _buildEditField('Fats (g)', _fatsController, LucideIcons.droplets),
              ] else ...[
                _buildSectionTitle('ACCOUNT'),
                _buildSettingItem(LucideIcons.target, 'My Goals', 'Weight, Calories, Macros', Colors.blue),
                _buildSettingItem(LucideIcons.bell, 'Notifications', 'Reminders, Alerts', Colors.orange),
                
                const SizedBox(height: 24),
                _buildSectionTitle('PREFERENCES'),
                _buildSettingItem(LucideIcons.shield, 'Privacy & Security', 'Data, Permissions', Colors.purple),
                _buildSettingItem(LucideIcons.fileText, 'Download Report', 'Health & Nutrition PDF', Colors.green, onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Generating health report... PDF will be ready soon.')),
                  );
                }),
                _buildSettingItem(LucideIcons.trash2, 'Clear Chat', 'Reset AI Coach history', Colors.red, onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chat history cleared.')),
                  );
                }),
              ],

              const SizedBox(height: 40),

              // Sign Out Button
              GestureDetector(
                onTap: () => FirebaseAuth.instance.signOut(),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.red.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.logOut, color: Colors.red, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Sign Out',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(color: Colors.grey, fontSize: 12),
          icon: Icon(icon, color: const Color(0xFF10B981), size: 20),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildGoalSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Goal',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildGoalOption('lose', 'Lose Weight'),
              const SizedBox(width: 8),
              _buildGoalOption('maintain', 'Maintain'),
              const SizedBox(width: 8),
              _buildGoalOption('gain', 'Gain Muscle'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoalOption(String value, String label) {
    final isSelected = _selectedGoal == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedGoal = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF10B981) : const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 16, top: 16),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: Colors.grey,
          letterSpacing: 2.0,
        ),
      ),
    );
  }

  Widget _buildSettingItem(IconData icon, String title, String subtitle, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
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
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}
