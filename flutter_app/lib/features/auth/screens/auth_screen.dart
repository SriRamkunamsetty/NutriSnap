import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_alert_banner.dart';
import '../../../core/widgets/animated_entry.dart';
import '../providers/user_provider.dart';
import '../providers/user_state.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isSignUp = false;
  bool _isForgotPassword = false;
  bool _isLoading = false;
  
  String? _authError;
  String? _authSuccess;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearMessages() {
    setState(() {
      _authError = null;
      _authSuccess = null;
    });
  }

  Future<void> _handleLocalAuth() async {
    _clearMessages();
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();

    setState(() => _isLoading = true);

    try {
      final localUser = LocalUser(
        uid: "local_user_${DateTime.now().millisecondsSinceEpoch}",
        email: email.isNotEmpty ? email : 'private.user@on-device.local',
        displayName: name.isNotEmpty ? name : 'NutriSnap User',
        emailVerified: true,
      );

      await ref.read(userNotifierProvider.notifier).login(localUser);
      setState(() => _authSuccess = 'Welcome! Your private on-device session is ready.');
    } catch (e) {
      setState(() => _authError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo & Header
                  AnimatedEntry(
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF22C55E).withOpacity(0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 38),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'NutriSnap AI',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '100% PRIVATE ON-DEVICE NUTRITION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.0,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Auth Card
                  AnimatedEntry(
                    delay: const Duration(milliseconds: 100),
                    child: AppCard(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isSignUp ? 'Create Private Profile' : 'On-Device Sign In',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'All your meals and photos stay on this phone.',
                            style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 20),

                          if (_isSignUp) ...[
                            AppTextField(
                              label: 'Your Name',
                              controller: _nameController,
                              prefixIcon: LucideIcons.user,
                              hint: 'e.g. Alex',
                            ),
                            const SizedBox(height: 16),
                          ],

                          AppTextField(
                            label: 'Email (Optional)',
                            controller: _emailController,
                            prefixIcon: LucideIcons.mail,
                            keyboardType: TextInputType.emailAddress,
                            hint: 'your.name@example.com',
                          ),
                          const SizedBox(height: 16),

                          AppTextField(
                            label: 'Password (Optional)',
                            controller: _passwordController,
                            prefixIcon: LucideIcons.lock,
                            obscureText: true,
                            hint: '••••••••',
                          ),
                          const SizedBox(height: 20),

                          // Privacy Reassurance
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFA7F3D0)),
                            ),
                            child: const Row(
                              children: [
                                Icon(LucideIcons.shieldCheck, color: Color(0xFF059669), size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Zero cloud tracking. Complete privacy.',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          if (_authError != null) ...[
                            AppAlertBanner(message: _authError!, isError: true),
                            const SizedBox(height: 16),
                          ],

                          if (_authSuccess != null) ...[
                            AppAlertBanner(message: _authSuccess!, isError: false),
                            const SizedBox(height: 16),
                          ],

                          AppButton(
                            text: _isSignUp ? 'Enter NutriSnap' : 'Start Private Session',
                            icon: LucideIcons.arrowRight,
                            isLoading: _isLoading,
                            onPressed: _handleLocalAuth,
                          ),
                          const SizedBox(height: 16),

                          GestureDetector(
                            onTap: () {
                              _clearMessages();
                              setState(() => _isSignUp = !_isSignUp);
                            },
                            child: Center(
                              child: Text(
                                _isSignUp ? 'Already have an account? Sign In' : "New user? Create Profile",
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF22C55E),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
