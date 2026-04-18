import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/user_profile.dart';
import '../../../core/models/scan_result.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/providers/unsaved_changes_provider.dart';
import '../../auth/providers/user_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final ImagePicker _picker = ImagePicker();

  bool _isEditing = false;
  bool _isAnalyzing = false;
  bool _isUploadingProfile = false;
  bool _isUploadingAIAvatar = false;
  bool _isClearing = false;
  bool _isGeneratingReport = false;
  bool _showReportSuccess = false;
  bool _showBodyScanSuccess = false;

  late int _height;
  late int _weight;
  late String _goal;
  late int _calorieLimit;
  late int _proteinGoal;
  late int _carbsGoal;
  late int _fatsGoal;
  late int _proteinPct;
  late int _carbsPct;
  late int _fatsPct;
  late int _waterGoal;
  
  // These track live edits to form state
  UserProfile? _localProfileCache;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _initFromProfile(ref.read(userNotifierProvider).profile);
  }

  void _initFromProfile(UserProfile? profile) {
    if (profile == null) return;
    _localProfileCache = profile;

    _height = profile.height?.toInt() ?? 175;
    _weight = profile.weight?.toInt() ?? 70;
    _goal = profile.goal?.name ?? 'lose';
    
    _calorieLimit = (profile.calorieLimit != null && profile.calorieLimit! > 0) ? profile.calorieLimit! : 2000;
    _proteinGoal = (profile.proteinGoal != null && profile.proteinGoal! > 0) ? profile.proteinGoal! : 150;
    _carbsGoal = (profile.carbsGoal != null && profile.carbsGoal! > 0) ? profile.carbsGoal! : 200;
    _fatsGoal = (profile.fatsGoal != null && profile.fatsGoal! > 0) ? profile.fatsGoal! : 70;
    
    _waterGoal = profile.waterGoal ?? 2500;

    _proteinPct = ((_proteinGoal * 4 / _calorieLimit) * 100).round();
    _carbsPct = ((_carbsGoal * 4 / _calorieLimit) * 100).round();
    _fatsPct = 100 - _proteinPct - _carbsPct;
    
    // Bounds fallback
    if (_proteinPct < 0) _proteinPct = 30;
    if (_carbsPct < 0) _carbsPct = 40;
    if (_fatsPct < 0) _fatsPct = 30;
  }

  void _setDirty(bool value) {
    setState(() => _isDirty = value);
    ref.read(unsavedChangesProvider.notifier).state = value;
  }

  void _recalculateMacrosFromPct() {
    setState(() {
      _proteinGoal = ((_calorieLimit * (_proteinPct / 100)) / 4).round();
      _carbsGoal = ((_calorieLimit * (_carbsPct / 100)) / 4).round();
      _fatsGoal = ((_calorieLimit * (_fatsPct / 100)) / 9).round();
    });
    _setDirty(true);
  }

  void _handleMacroPctChange(String field, int newValue) {
    setState(() {
      // (Keep existing macro pct calculations)
      int diff = 0;
      if (field == 'protein') {
        diff = newValue - _proteinPct;
        _proteinPct = newValue;
        
        int firstDist = _carbsPct - diff;
        if (firstDist < 0) {
          _carbsPct = 0;
          _fatsPct = _fatsPct + firstDist;
        } else {
          _carbsPct = firstDist;
        }
      } else if (field == 'carbs') {
        diff = newValue - _carbsPct;
        _carbsPct = newValue;
        
        int firstDist = _proteinPct - diff;
        if (firstDist < 0) {
          _proteinPct = 0;
          _fatsPct = _fatsPct + firstDist;
        } else {
          _proteinPct = firstDist;
        }
      } else if (field == 'fats') {
        diff = newValue - _fatsPct;
        _fatsPct = newValue;
        
        int firstDist = _carbsPct - diff;
        if (firstDist < 0) {
          _carbsPct = 0;
          _proteinPct = _proteinPct + firstDist;
        } else {
          _carbsPct = firstDist;
        }
      }
      
      if (_proteinPct < 0) _proteinPct = 0;
      if (_carbsPct < 0) _carbsPct = 0;
      if (_fatsPct < 0) _fatsPct = 0;

      final total = _proteinPct + _carbsPct + _fatsPct;
      if (total > 100) {
         if (field != 'protein' && _proteinPct > 0) _proteinPct -= (total - 100);
         else if (field != 'carbs' && _carbsPct > 0) _carbsPct -= (total - 100);
         else if (field != 'fats' && _fatsPct > 0) _fatsPct -= (total - 100);
      }
    });
    _recalculateMacrosFromPct();
  }

  double _calculateBMI(int h, int w) {
    if (h == 0 || w == 0) return 0.0;
    return (w / ((h / 100) * (h / 100)));
  }

  Map<String, dynamic> _getBMIDetails(double bmi) {
    if (bmi < 18.5) return {'label': 'Underweight', 'color': Colors.blue.shade500, 'bg': Colors.blue.shade50};
    if (bmi < 25) return {'label': 'Healthy', 'color': Colors.green.shade600, 'bg': Colors.green.shade50};
    if (bmi < 30) return {'label': 'Overweight', 'color': Colors.orange.shade500, 'bg': Colors.orange.shade50};
    return {'label': 'Obese', 'color': Colors.red.shade500, 'bg': Colors.red.shade50};
  }

  Future<void> _handleSave() async {
    HapticFeedback.mediumImpact();
    
    // Strict Validation
    if (_height < 50 || _height > 300) {
      UIFeedback.showError(context, 'Please enter a valid height (50 - 300 cm).');
      return;
    }
    if (_weight < 20 || _weight > 400) {
      UIFeedback.showError(context, 'Please enter a valid weight (20 - 400 kg).');
      return;
    }
    if (_calorieLimit < 500 || _calorieLimit > 10000) {
      UIFeedback.showError(context, 'Calorie limit must be between 500 and 10,000 kcals.');
      return;
    }
    if (_waterGoal < 500 || _waterGoal > 15000) {
      UIFeedback.showError(context, 'Water goal must be between 500 and 15,000 ml.');
      return;
    }

    try {
      final finalBMI = _calculateBMI(_height, _weight);
      final profileNotifier = ref.read(userNotifierProvider.notifier);
      final currentProfile = ref.read(userNotifierProvider).profile;
      
      if (currentProfile != null) {
        await profileNotifier.updateProfile(
           currentProfile.copyWith(
             height: _height.toDouble(),
             weight: _weight.toDouble(),
             bmi: double.parse(finalBMI.toStringAsFixed(1)),
             goal: GoalExtension.fromString(_goal),
             calorieLimit: _calorieLimit,
             proteinGoal: _proteinGoal,
             carbsGoal: _carbsGoal,
             fatsGoal: _fatsGoal,
             proteinPct: _proteinPct.toDouble(),
             carbsPct: _carbsPct.toDouble(),
             fatsPct: _fatsPct.toDouble(),
             waterGoal: _waterGoal,
           )
        );
      }
      
      setState(() {
        _isEditing = false;
        _isDirty = false;
      });
      ref.read(unsavedChangesProvider.notifier).state = false;
      
      UIFeedback.showSuccess(context, 'Profile updated successfully');
    } catch (_) {
      UIFeedback.showError(context, 'Failed to update profile. Please try again.');
    }
  }

  Future<void> _handleProfileImageChange() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 70);
    if (image == null) return;

    setState(() => _isUploadingProfile = true);
    HapticFeedback.mediumImpact();
    UIFeedback.showInfo(context, 'Uploading profile image...');

    try {
      final storageService = ref.read(storageServiceProvider);
      final url = await storageService.uploadProfileImage(File(image.path));
      
      final currentProfile = ref.read(userNotifierProvider).profile;
      if (currentProfile != null) {
        await ref.read(userNotifierProvider.notifier).updateProfile(currentProfile.copyWith(photoURL: url));
      }
      
      UIFeedback.showSuccess(context, 'Profile image updated!');
    } catch (_) {
      UIFeedback.showError(context, 'Failed to upload image.');
    } finally {
      if (mounted) setState(() => _isUploadingProfile = false);
    }
  }

  Future<void> _handleAIAvatarChange() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 70);
    if (image == null) return;

    setState(() => _isUploadingAIAvatar = true);
    HapticFeedback.mediumImpact();
    UIFeedback.showInfo(context, 'Uploading AI avatar...');

    try {
      final storageService = ref.read(storageServiceProvider);
      final url = await storageService.uploadAIAvatar(File(image.path));
      
      final currentProfile = ref.read(userNotifierProvider).profile;
      if (currentProfile != null) {
        await ref.read(userNotifierProvider.notifier).updateProfile(currentProfile.copyWith(aiAvatarURL: url));
      }

      UIFeedback.showSuccess(context, 'AI Avatar updated!');
    } catch (_) {
      UIFeedback.showError(context, 'Failed to upload AI avatar.');
    } finally {
      if (mounted) setState(() => _isUploadingAIAvatar = false);
    }
  }

  Future<void> _handleBodyImageChange() async {
     final XFile? image = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1024, maxHeight: 1024, imageQuality: 70);
     if (image == null) return;

     setState(() => _isAnalyzing = true);
     HapticFeedback.mediumImpact();
     UIFeedback.showInfo(context, 'Analyzing body scan...');

     try {
       final storageService = ref.read(storageServiceProvider);
       final geminiService = ref.read(geminiServiceProvider);
       
       final bytes = await image.readAsBytes();
       // Use geminiService.analyzeBodyImage -> returns {bodyType, fatEstimate}
       final analysis = await geminiService.analyzeBodyImage(bytes, 'image/jpeg');
       
       final bodyScanURL = await storageService.uploadBodyImage(File(image.path));
       
       // Update Profile
       final currentProfile = ref.read(userNotifierProvider).profile;
       if (currentProfile != null) {
         await ref.read(userNotifierProvider.notifier).updateProfile(
           currentProfile.copyWith(
             bodyType: BodyTypeExtension.fromString(analysis['bodyType'] as String?),
             fatEstimate: (analysis['fatEstimate'] as num?)?.toDouble() ?? 0.0,
             bodyScanURL: bodyScanURL,
           )
         );
       }

       // Save to History
       final scan = ScanResult(
         id: '',
         userId: '',
         foodName: 'Body Scan',
         type: 'person',
         description: 'Body Type: \${analysis["bodyType"]}, Fat Estimate: \${analysis["fatEstimate"]}%',
         calories: 0,
         protein: 0,
         carbs: 0,
         fats: 0,
         fatEstimate: (analysis['fatEstimate'] as num?)?.toDouble() ?? 0.0,
         confidence: 1.0,
         imageUrl: bodyScanURL,
         timestamp: DateTime.now().toIso8601String(),
       );
       await storageService.saveScanResult(scan);

       UIFeedback.showSuccess(context, 'Body scan complete!');

       setState(() {
         _showBodyScanSuccess = true;
       });
       HapticFeedback.lightImpact();

       Future.delayed(const Duration(seconds: 4), () {
         if (mounted) setState(() => _showBodyScanSuccess = false);
       });

     } catch (_) {
       UIFeedback.showError(context, 'Body analysis failed. Please try again.');
     } finally {
       if (mounted) setState(() => _isAnalyzing = false);
     }
  }

  Future<void> _handleClearChat() async {
    setState(() => _isClearing = true);
    HapticFeedback.mediumImpact();
    try {
      await ref.read(storageServiceProvider).clearChatHistory();
      if (mounted) Navigator.of(context).pop(); // Close dialog
      UIFeedback.showSuccess(context, 'Chat history cleared.');
    } catch (_) {
       UIFeedback.showError(context, 'Failed to clear chat history.');
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _handleSignOut() async {
     HapticFeedback.mediumImpact();
     try {
       await ref.read(firebaseServiceProvider).auth.signOut();
     } catch (_) {}
  }

  void _showClearChatDialog() {
     showDialog(
       context: context,
       builder: (context) {
         return AlertDialog(
           backgroundColor: Colors.white,
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
           title: Column(
             children: [
               Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(24)), child: Icon(LucideIcons.trash2, color: Colors.red.shade500, size: 32)),
               const SizedBox(height: 16),
               const Text('Clear Chat History?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
             ],
           ),
           content: const Text('This will permanently delete all your conversations with the AI Coach. This action cannot be undone.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
           actions: [
             Row(
               children: [
                 Expanded(child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)))),
                 Expanded(child: ElevatedButton(onPressed: _isClearing ? null : _handleClearChat, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade500, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: _isClearing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Clear All', style: TextStyle(fontWeight: FontWeight.bold)))),
               ],
             )
           ],
         );
       }
     );
  }

  Widget _buildTextField(String label, IconData icon, String value, Function(String) onChanged, {TextInputType type = TextInputType.text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.blue.shade500),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: value,
            keyboardType: type,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(userNotifierProvider);
    final profile = userState.profile;
    
    // Ensure form holds accurate state if switching tabs and coming back
    if (profile != null && profile != _localProfileCache) {
      _initFromProfile(profile);
    }

    final bmiVal = _isEditing ? _calculateBMI(_height, _weight) : (profile?.bmi ?? 0.0);
    final bmiDetails = _getBMIDetails(bmiVal);
    final dailySummarySync = ref.watch(dailySummaryStreamProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              children: [
                // 1. Profile Header
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // User Profile Pic
                        Column(
                          children: [
                            InkWell(
                              onTap: _handleProfileImageChange,
                              borderRadius: BorderRadius.circular(32),
                              child: Container(
                                width: 96, height: 96,
                                decoration: BoxDecoration(color: Colors.green.shade500, borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white, width: 4), boxShadow: [BoxShadow(color: Colors.green.shade500.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
                                clipBehavior: Clip.hardEdge,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (profile?.photoURL != null && profile!.photoURL.isNotEmpty)
                                      Image.network(profile.photoURL, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Center(child: Icon(LucideIcons.user, color: Colors.white, size: 40)))
                                    else
                                      Center(child: Text((profile?.displayName ?? 'U').substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white))),
                                    if (_isUploadingProfile)
                                      Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
                                    Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: Icon(LucideIcons.camera, size: 12, color: Colors.green.shade600)))
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('YOUR AVATAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
                          ],
                        ),
                        const SizedBox(width: 32),
                        // AI Coach Pic
                        Column(
                          children: [
                            InkWell(
                              onTap: _handleAIAvatarChange,
                              borderRadius: BorderRadius.circular(32),
                              child: Container(
                                width: 96, height: 96,
                                decoration: BoxDecoration(color: Colors.purple.shade500, borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white, width: 4), boxShadow: [BoxShadow(color: Colors.purple.shade500.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
                                clipBehavior: Clip.hardEdge,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (profile?.aiAvatarURL != null && profile!.aiAvatarURL!.isNotEmpty)
                                      Image.network(profile.aiAvatarURL!, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Center(child: Icon(LucideIcons.bot, color: Colors.white, size: 40)))
                                    else
                                      const Center(child: Icon(LucideIcons.bot, color: Colors.white, size: 40)),
                                    if (_isUploadingAIAvatar)
                                      Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
                                    Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: Icon(LucideIcons.camera, size: 12, color: Colors.purple.shade600)))
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('AI AVATAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(userState.firebaseUser?.email ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    if (!_isEditing)
                      ElevatedButton.icon(
                        onPressed: () {
                           HapticFeedback.lightImpact();
                           setState(() => _isEditing = true);
                        },
                        icon: const Icon(LucideIcons.user, size: 16),
                        label: const Text('Edit Profile'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0, side: const BorderSide(color: AppColors.border)),
                      )
                  ],
                ),
                const SizedBox(height: 32),

                // 2. Health Metrics Card
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.green.shade500, shape: BoxShape.circle), child: Container(decoration: BoxDecoration(color: Colors.green.shade500, shape: BoxShape.circle)).animate(onPlay: (controller) => controller.repeat()).scale(begin: const Offset(1, 1), end: const Offset(2, 2)).fadeOut()),
                              const SizedBox(width: 8),
                              const Text('HEALTH INDEX', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: bmiDetails['bg'], borderRadius: BorderRadius.circular(16)),
                            child: Text((bmiDetails['label'] as String).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: bmiDetails['color'], letterSpacing: 1.0)),
                          )
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(bmiVal.toStringAsFixed(1), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -2)),
                          const SizedBox(width: 8),
                          const Text('BMI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Progress Bar Visualizer
                      Container(
                        height: 16,
                        decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(8)),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                             final percent = (bmiVal / 40.0).clamp(0.0, 1.0);
                             return Stack(
                               children: [
                                  // Underweight Bound
                                  Positioned(left: constraints.maxWidth * 0.4625, top: 0, bottom: 0, child: Container(width: 2, color: Colors.white)),
                                  Positioned(left: constraints.maxWidth * (0.4625 + 0.1625), top: 0, bottom: 0, child: Container(width: 2, color: Colors.white)),
                                  Positioned(left: constraints.maxWidth * (0.4625 + 0.1625 + 0.125), top: 0, bottom: 0, child: Container(width: 2, color: Colors.white)),
                                  AnimatedContainer(
                                    duration: const Duration(seconds: 1),
                                    curve: Curves.easeOutCubic,
                                    width: constraints.maxWidth * percent,
                                    height: 16,
                                    decoration: BoxDecoration(color: bmiDetails['color'], borderRadius: BorderRadius.circular(8)),
                                  )
                               ],
                             );
                          }
                        )
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                           Text('UNDER', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
                           Text('HEALTHY', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
                           Text('OVER', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Body Type / Fat Estimate Boxes
                      Row(
                        children: [
                           Expanded(
                             child: Container(
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                               child: Column(
                                 children: [
                                   const Text('BODY TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
                                   const SizedBox(height: 4),
                                   Text((profile?.bodyType ?? 'Unknown').toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                 ],
                               ),
                             ),
                           ),
                           const SizedBox(width: 16),
                           Expanded(
                             child: Container(
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                               child: Column(
                                 children: [
                                   const Text('FAT ESTIMATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
                                   const SizedBox(height: 4),
                                   Text(profile?.fatEstimate != null && profile!.fatEstimate! > 0 ? '\${profile.fatEstimate}%' : '--', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                 ],
                               ),
                             ),
                           ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Analyze Body Button
                      InkWell(
                        onTap: _isAnalyzing ? null : _handleBodyImageChange,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isAnalyzing)
                                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green))
                              else
                                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)), child: Icon(LucideIcons.sparkles, color: Colors.green.shade600, size: 16)),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_isAnalyzing ? 'AI is Analyzing Body...' : 'AI Body Scan', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                  if (!_isAnalyzing)
                                    Text('POWERED BY GEMINI 3.1 PRO', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.green.shade500, letterSpacing: 1.0)),
                                ],
                              )
                            ],
                          ),
                        ),
                      )
                    ],
                  )
                ),
                const SizedBox(height: 32),

                // 3. EDIT MODE CONTROLS
                if (_isEditing) ...[
                  // Height / Weight Row
                  Row(
                    children: [
                      Expanded(child: _buildTextField('HEIGHT (CM)', LucideIcons.ruler, _height.toString(), (v) { setState(() { _height = int.tryParse(v) ?? 0; }); _setDirty(true); }, type: TextInputType.number)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField('WEIGHT (KG)', LucideIcons.scale, _weight.toString(), (v) { setState(() { _weight = int.tryParse(v) ?? 0; }); _setDirty(true); }, type: TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Goal Selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.border)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(LucideIcons.target, size: 16, color: Colors.purple.shade500),
                            const SizedBox(width: 8),
                            const Text('YOUR GOAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _goal,
                            isExpanded: true,
                            icon: const Icon(LucideIcons.chevronDown, color: AppColors.textTertiary),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontFamily: 'Inter'),
                            items: const [
                              DropdownMenuItem(value: 'lose', child: Text('Lose Weight')),
                              DropdownMenuItem(value: 'maintain', child: Text('Maintain Weight')),
                              DropdownMenuItem(value: 'gain', child: Text('Gain Weight')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() { _goal = v; });
                                _setDirty(true);
                              }
                            },
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Calorie Limit Slider
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.border)),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(LucideIcons.flame, color: Colors.red.shade500, size: 20),
                                const SizedBox(width: 8),
                                const Text('Daily Calorie Limit', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                              ],
                            ),
                            Row(
                              children: [
                                Text('$_calorieLimit', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                                const SizedBox(width: 4),
                                const Text('KCAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 16),
                        SliderTheme(
                          data: SliderThemeData(activeTrackColor: Colors.green.shade600, inactiveTrackColor: AppColors.surfaceMuted, thumbColor: Colors.green.shade600, overlayColor: Colors.green.shade600.withOpacity(0.2)),
                          child: Slider(
                            value: _calorieLimit.toDouble().clamp(1000, 5000),
                            min: 1000, max: 5000, divisions: 80,
                            onChanged: (v) {
                               setState(() {
                                  _calorieLimit = v.round();
                               });
                               _recalculateMacrosFromPct();
                            },
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Macro Sliders
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.border)),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(LucideIcons.target, color: Colors.blue.shade500, size: 20),
                            const SizedBox(width: 8),
                            const Text('Macronutrient Split (%)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildMacroSlider('PROTEIN', _proteinPct, _proteinGoal, Colors.blue.shade500, (v) => _handleMacroPctChange('protein', v.toInt())),
                        const SizedBox(height: 16),
                        _buildMacroSlider('CARBS', _carbsPct, _carbsGoal, Colors.orange.shade500, (v) => _handleMacroPctChange('carbs', v.toInt())),
                        const SizedBox(height: 16),
                        _buildMacroSlider('FATS', _fatsPct, _fatsGoal, Colors.purple.shade500, (v) => _handleMacroPctChange('fats', v.toInt())),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Water Slider
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.border)),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(LucideIcons.droplets, color: Colors.blue.shade500, size: 20),
                                const SizedBox(width: 8),
                                const Text('Daily Water Goal', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                              ],
                            ),
                            Row(
                              children: [
                                Text('$_waterGoal', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                                const SizedBox(width: 4),
                                const Text('ML', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 16),
                        SliderTheme(
                          data: SliderThemeData(activeTrackColor: Colors.blue.shade600, inactiveTrackColor: AppColors.surfaceMuted, thumbColor: Colors.blue.shade600, overlayColor: Colors.blue.shade600.withOpacity(0.2)),
                          child: Slider(
                            value: _waterGoal.toDouble().clamp(500, 10000),
                            min: 500, max: 10000, divisions: 38,
                            onChanged: (v) {
                               setState(() {
                                  _waterGoal = v.round();
                               });
                               _setDirty(true);
                            },
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Save / Cancel Row
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            _setDirty(false);
                            setState(() {
                               _isEditing = false;
                               _initFromProfile(_localProfileCache);
                            });
                          },
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                          child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                        )
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isDirty ? _handleSave : null,
                          icon: const Icon(LucideIcons.save, size: 18),
                          label: const Text('Save Changes'),
                          style: ElevatedButton.styleFrom(
                             backgroundColor: Colors.green.shade600,
                             foregroundColor: Colors.white,
                             disabledBackgroundColor: AppColors.surfaceMuted,
                             disabledForegroundColor: AppColors.textTertiary,
                             padding: const EdgeInsets.symmetric(vertical: 20),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                             elevation: 0,
                          ),
                        )
                      )
                    ],
                  ),
                  const SizedBox(height: 32),
                ] else ...[
                  // Nutritional Goals Read-Only Summary
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))]),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.blue.shade500, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                const Text('NUTRITIONAL GOALS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
                              ],
                            ),
                            Row(
                              children: [
                                Icon(LucideIcons.flame, color: Colors.red.shade500, size: 14),
                                const SizedBox(width: 4),
                                Text('${profile?.calorieLimit ?? 2000} kcal', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Expanded(child: _buildMacroSummaryBox('Protein', LucideIcons.beef, _proteinGoal, _proteinPct, dailySummarySync?.totalProtein ?? 0, Colors.blue)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMacroSummaryBox('Carbs', LucideIcons.wheat, _carbsGoal, _carbsPct, dailySummarySync?.totalCarbs ?? 0, Colors.orange)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMacroSummaryBox('Fats', LucideIcons.droplets, _fatsGoal, _fatsPct, dailySummarySync?.totalFats ?? 0, Colors.purple)),
                          ],
                        )
                      ],
                    )
                  ),
                  const SizedBox(height: 32),

                  // Health Report Section
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)), child: Icon(LucideIcons.fileText, color: Colors.blue.shade600, size: 20)),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Health Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                                const Text('EXPORT YOUR DATA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
                              ],
                            )
                          ]
                        ),
                        const SizedBox(height: 16),
                        const Text('Generate a comprehensive PDF report of your nutrition, scans, and health trends.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _isGeneratingReport ? null : () async {
                             setState(() => _isGeneratingReport = true);
                             HapticFeedback.mediumImpact();
                             await Future.delayed(const Duration(seconds: 2)); // Mock generation
                             setState(() { _isGeneratingReport = false; _showReportSuccess = true; });
                             HapticFeedback.lightImpact();
                             Future.delayed(const Duration(seconds: 4), () { if(mounted) setState(() => _showReportSuccess = false); });
                          },
                          icon: _isGeneratingReport ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(LucideIcons.fileText, size: 20),
                          label: Text(_isGeneratingReport ? 'Generating Report...' : 'Download Health Report (PDF)'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), elevation: 0),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Sign Out
                  ElevatedButton.icon(
                    onPressed: _handleSignOut,
                    icon: const Icon(LucideIcons.logOut, size: 20),
                    label: const Text('Sign Out'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red.shade500, minimumSize: const Size(double.infinity, 64), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)), elevation: 0, side: const BorderSide(color: AppColors.border)),
                  ),
                  const SizedBox(height: 16),

                  // Clear Chat History
                  TextButton.icon(
                    onPressed: _showClearChatDialog,
                    icon: const Icon(LucideIcons.trash2, size: 20),
                    label: const Text('Clear AI Chat History'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary, minimumSize: const Size(double.infinity, 64), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32))),
                  )
                ],
              ],
            ),
          ),

          // TOASTS
          if (_showReportSuccess)
             Positioned(
               bottom: 24, left: 24, right: 24,
               child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                 decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(16)),
                 child: Row(
                   children: [
                     Container(width: 32, height: 32, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: const Icon(LucideIcons.fileText, color: Colors.white, size: 18)),
                     const SizedBox(width: 12),
                     const Text('Report downloaded successfully', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                   ],
                 ),
               ).animate().slideY(begin: 1.0, end: 0, duration: 300.ms).fadeIn(),
             ),
          
          if (_showBodyScanSuccess)
            Positioned(
               top: 24, left: 24, right: 24,
               child: SafeArea(
                 child: Container(
                   padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                   decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(16)),
                   child: Row(
                     children: [
                       Container(width: 32, height: 32, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 18)),
                       const SizedBox(width: 12),
                       const Expanded(child: Text('Scan Successful! Data Updated', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                     ],
                   ),
                 ).animate().slideY(begin: -1.0, end: 0, duration: 300.ms).fadeIn(),
               ),
             ),
        ],
      ),
    );
  }

  Widget _buildMacroSlider(String label, int pct, int goal, Color color, Function(double) onChanged) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
                Text('$pct%', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
            Text('${goal}g', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(activeTrackColor: color, inactiveTrackColor: AppColors.surfaceMuted, thumbColor: color, overlayColor: color.withOpacity(0.2)),
          child: Slider(value: pct.toDouble().clamp(0, 100), min: 0, max: 100, onChanged: onChanged),
        )
      ],
    );
  }

  Widget _buildMacroSummaryBox(String label, IconData icon, int goal, int pct, int current, MaterialColor color) {
    final progress = (goal > 0) ? (current / goal).clamp(0.0, 1.0) : 0.0;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.shade50.withOpacity(0.5), borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)),
      child: Column(
        children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 16, color: color.shade500)),
          const SizedBox(height: 12),
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Text('${goal}g', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          Text('$pct%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color.shade500)),
          const SizedBox(height: 12),
          Container(
             height: 6,
             decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(3)),
             child: LayoutBuilder(
               builder: (context, constraints) {
                 return Stack(
                   children: [
                     AnimatedContainer(
                       duration: const Duration(seconds: 1),
                       width: constraints.maxWidth * progress,
                       height: 6,
                       decoration: BoxDecoration(color: color.shade500, borderRadius: BorderRadius.circular(3))
                     )
                   ],
                 );
               }
             )
          ),
          const SizedBox(height: 8),
          Text('${current}g / ${goal}g', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 0.5)),
        ],
      )
    );
  }
}
