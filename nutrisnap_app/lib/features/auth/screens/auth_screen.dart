import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/utils/firebase_exception_handler.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_alert_banner.dart';
import '../../../core/widgets/animated_entry.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isSignUp = false;
  bool _isForgotPassword = false;
  bool _isLoading = false;
  
  String? _authError;
  String? _authSuccess;

  @override
  void dispose() {
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

  Future<void> _handleEmailAuth() async {
    _clearMessages();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _authError = 'Please fill in all fields.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = ref.read(firebaseServiceProvider).auth;
      if (_isSignUp) {
        final userCredential = await auth.createUserWithEmailAndPassword(email: email, password: password);
        await userCredential.user?.sendEmailVerification();
        setState(() {
          _authSuccess = 'Account created! Please check your email for a verification link.';
        });
      } else {
        await auth.signInWithEmailAndPassword(email: email, password: password);
      }
    } catch (e) {
      setState(() => _authError = FirebaseExceptionHandler.handleException(e, 'EmailAuth'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    _clearMessages();
    final email = _emailController.text.trim();
    
    if (email.isEmpty) {
      setState(() => _authError = 'Please enter your email.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = ref.read(firebaseServiceProvider).auth;
      await auth.sendPasswordResetEmail(email: email);
      setState(() => _authSuccess = 'Password reset link sent to your email!');
    } catch (e) {
      setState(() => _authError = FirebaseExceptionHandler.handleException(e, 'PasswordReset'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOAuth(AuthProvider provider) async {
    _clearMessages();
    setState(() => _isLoading = true);

    try {
      final auth = ref.read(firebaseServiceProvider).auth;
      await auth.signInWithPopup(provider);
    } catch (e) {
      setState(() => _authError = FirebaseExceptionHandler.handleException(e, 'OAuth'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Accents
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withOpacity(0.08),
                boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.08), blurRadius: 120, spreadRadius: 60)],
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.05),
                boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 120, spreadRadius: 60)],
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScaleIn(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(color: Colors.green.shade600.withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 8))
                          ],
                        ),
                        child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 40),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const AnimatedFadeIn(
                      delay: Duration(milliseconds: 200),
                      child: Text(
                        'NutriSnap AI',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.0),
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedFadeIn(
                      delay: const Duration(milliseconds: 300),
                      child: Text(
                        'YOUR PERSONAL NUTRITIONIST',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade400, letterSpacing: 2.0),
                      ),
                    ),
                    const SizedBox(height: 32),

                    AnimatedFadeSlide(
                      delay: const Duration(milliseconds: 300),
                      child: AppCard(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _isForgotPassword 
                            ? _buildForgotPasswordForm() 
                            : _buildAuthForm(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                    Text(
                      'BY CONTINUING, YOU AGREE TO OUR TERMS & PRIVACY',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade400, letterSpacing: 1.0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthForm() {
    return Column(
      key: const ValueKey('auth_form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _emailController,
          hintText: 'Email Address',
          icon: LucideIcons.mail,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _passwordController,
          hintText: 'Password',
          icon: LucideIcons.lock,
          obscureText: true,
        ),
        
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              _clearMessages();
              setState(() => _isForgotPassword = true);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: Colors.green.shade600,
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            child: const Text('Forgot Password?'),
          ),
        ),

        if (_authError != null) AppAlertBanner(message: _authError!, isError: true),
        if (_authSuccess != null) AppAlertBanner(message: _authSuccess!, isError: false),
        
        const SizedBox(height: 8),

        PrimaryButton(
          text: _isSignUp ? 'Create Account' : 'Sign In',
          icon: LucideIcons.arrowRight,
          onPressed: _isLoading ? null : _handleEmailAuth,
          isLoading: _isLoading,
        ),

        const SizedBox(height: 24),
        _buildDivider('OR CONTINUE WITH'),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                text: 'Google',
                icon: LucideIcons.chrome, 
                onPressed: _isLoading ? null : () => _handleOAuth(GoogleAuthProvider()),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SecondaryButton(
                isSolid: true,
                text: 'GitHub',
                icon: LucideIcons.github,
                onPressed: _isLoading ? null : () => _handleOAuth(GithubAuthProvider()..addScope('read:user')..addScope('user:email')),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            _clearMessages();
            setState(() => _isSignUp = !_isSignUp);
          },
          style: TextButton.styleFrom(foregroundColor: Colors.grey.shade500),
          child: Text(
            _isSignUp ? 'Already have an account? Sign In' : "Don't have an account? Sign Up",
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPasswordForm() {
    return Column(
      key: const ValueKey('forgot_password_form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Reset Password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Enter your email to receive a reset link.', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        const SizedBox(height: 24),
        
        AppTextField(
          controller: _emailController,
          hintText: 'Email Address',
          icon: LucideIcons.mail,
          keyboardType: TextInputType.emailAddress,
        ),

        const SizedBox(height: 24),
        if (_authError != null) AppAlertBanner(message: _authError!, isError: true),
        if (_authSuccess != null) AppAlertBanner(message: _authSuccess!, isError: false),
        if (_authError != null || _authSuccess != null) const SizedBox(height: 16),

        PrimaryButton(
          text: 'Send Reset Link',
          icon: LucideIcons.arrowRight,
          onPressed: _isLoading ? null : _handleForgotPassword,
          isLoading: _isLoading,
        ),
        
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            _clearMessages();
            setState(() => _isForgotPassword = false);
          },
          style: TextButton.styleFrom(foregroundColor: Colors.grey.shade400),
          child: const Text('Back to Login', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildDivider(String text) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade200)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            text,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade400, letterSpacing: 2.0),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade200)),
      ],
    );
  }
}
