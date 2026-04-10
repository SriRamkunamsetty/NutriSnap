import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../services/firebase_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _isForgotPassword = false;
  bool _isLoading = false;
  String? _error;
  String? _success;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();

  Future<void> _handleAuth() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });

    try {
      if (_isForgotPassword) {
        await _firebaseService.sendPasswordReset(_emailController.text.trim());
        setState(() => _success = 'Password reset link sent to your email!');
      } else if (_isLogin) {
        await _firebaseService.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      } else {
        await _firebaseService.signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text.trim(),
          _nameController.text.trim(),
        );
        await _firebaseService.sendEmailVerification();
        setState(() => _success = 'Account created! Please verify your email.');
      }
    } catch (e) {
      setState(() => _error = _getFriendlyErrorMessage(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSocialLogin(String provider) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (provider == 'google') {
        await _firebaseService.signInWithGoogle();
      } else {
        await _firebaseService.signInWithGithub();
      }
    } catch (e) {
      setState(() => _error = _getFriendlyErrorMessage(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getFriendlyErrorMessage(String error) {
    if (error.contains('user-not-found')) return 'No account found with this email.';
    if (error.contains('wrong-password')) return 'Incorrect password.';
    if (error.contains('email-already-in-use')) return 'Email already in use.';
    if (error.contains('invalid-email')) return 'Invalid email address.';
    if (error.contains('weak-password')) return 'Password is too weak.';
    return 'An unexpected error occurred. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Stack(
        children: [
          // Background Accents (Matching Web)
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo Section
                    Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withOpacity(0.3),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 40),
                        ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                        const SizedBox(height: 24),
                        Text(
                          'NutriSnap AI',
                          style: GoogleFonts.outfit(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          'YOUR PERSONAL NUTRITIONIST',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.grey.withOpacity(0.5),
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 48),

                    // Auth Card
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                        border: Border.all(color: Colors.white),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isForgotPassword) ...[
                            Text(
                              'Reset Password',
                              style: GoogleFonts.outfit(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Enter your email to receive a reset link.',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),

                          if (!_isLogin && !_isForgotPassword)
                            _buildTextField(
                              controller: _nameController,
                              hint: 'Full Name',
                              icon: LucideIcons.user,
                            ),
                          
                          if (!_isLogin && !_isForgotPassword) const SizedBox(height: 16),

                          _buildTextField(
                            controller: _emailController,
                            hint: 'Email Address',
                            icon: LucideIcons.mail,
                            keyboardType: TextInputType.emailAddress,
                          ),

                          if (!_isForgotPassword) ...[
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _passwordController,
                              hint: 'Password',
                              icon: LucideIcons.lock,
                              isPassword: true,
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => setState(() {
                                  _isForgotPassword = true;
                                  _error = null;
                                  _success = null;
                                }),
                                child: Text(
                                  'Forgot Password?',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ),
                          ],

                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            _buildStatusMessage(_error!, Colors.red, LucideIcons.alertCircle),
                          ],

                          if (_success != null) ...[
                            const SizedBox(height: 16),
                            _buildStatusMessage(_success!, Colors.green, LucideIcons.checkCircle2),
                          ],

                          const SizedBox(height: 24),

                          // Main Action Button
                          GestureDetector(
                            onTap: _isLoading ? null : _handleAuth,
                            child: Container(
                              height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withOpacity(0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _isForgotPassword
                                                ? 'Send Reset Link'
                                                : (_isLogin ? 'Sign In' : 'Create Account'),
                                            style: GoogleFonts.inter(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(LucideIcons.arrowRight, color: Colors.white, size: 18),
                                        ],
                                      ),
                              ),
                            ),
                          ),

                          if (_isForgotPassword) ...[
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: () => setState(() {
                                  _isForgotPassword = false;
                                  _error = null;
                                  _success = null;
                                }),
                                child: Text(
                                  'Back to Login',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ],

                          if (!_isForgotPassword) ...[
                            const SizedBox(height: 32),
                            // Divider
                            Row(
                              children: [
                                Expanded(child: Divider(color: Colors.grey.withOpacity(0.1))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    'OR CONTINUE WITH',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.grey.withOpacity(0.4),
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: Colors.grey.withOpacity(0.1))),
                              ],
                            ),

                            const SizedBox(height: 32),

                            // Social Buttons
                            Row(
                              children: [
                                _buildSocialButton(
                                  'google',
                                  'Google',
                                  const Color(0xFFF7F8FA),
                                  const Color(0xFF0F172A),
                                  Image.network(
                                    'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                    width: 18,
                                    height: 18,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                _buildSocialButton(
                                  'github',
                                  'GitHub',
                                  const Color(0xFF0F172A),
                                  Colors.white,
                                  const Icon(LucideIcons.github, size: 18, color: Colors.white),
                                ),
                              ],
                            ),

                            const SizedBox(height: 32),

                            // Toggle Sign In / Sign Up
                            Center(
                              child: TextButton(
                                onPressed: () => setState(() {
                                  _isLogin = !_isLogin;
                                  _error = null;
                                  _success = null;
                                }),
                                child: RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
                                    children: [
                                      TextSpan(text: _isLogin ? "Don't have an account? " : "Already have an account? "),
                                      TextSpan(
                                        text: _isLogin ? "Sign Up" : "Sign In",
                                        style: const TextStyle(
                                          color: Color(0xFF10B981),
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),
                    Text(
                      'BY CONTINUING, YOU AGREE TO OUR TERMS & PRIVACY',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey.withOpacity(0.4),
                        letterSpacing: 1.5,
                      ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(color: Colors.grey.withOpacity(0.5), fontWeight: FontWeight.w500),
          border: InputBorder.none,
          icon: Icon(icon, color: Colors.grey.withOpacity(0.5), size: 18),
        ),
      ),
    );
  }

  Widget _buildStatusMessage(String message, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton(String id, String label, Color bg, Color text, Widget icon) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _handleSocialLogin(id),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.withOpacity(0.05)),
            boxShadow: [
              if (bg == Colors.white)
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
