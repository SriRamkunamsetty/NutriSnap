import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

class NutriSnapApp extends StatelessWidget {
  const NutriSnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NutriSnap AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const NutriSnapRootApp(),
    );
  }
}

/// Flutter conversion of `src/App.tsx`.
///
/// This file intentionally mirrors the web file responsibilities:
/// - global app gate (loading/authenticated/unauthenticated)
/// - authentication form state (sign in/sign up/forgot password)
/// - friendly auth error mapping
/// - onboarding vs main navigation gate
/// - email verification banner and resend interaction
class NutriSnapRootApp extends StatefulWidget {
  const NutriSnapRootApp({super.key});

  @override
  State<NutriSnapRootApp> createState() => _NutriSnapRootAppState();
}

enum _SessionState { loading, signedOut, signedIn }
enum _AuthMode { signIn, signUp, forgotPassword }

class _NutriSnapRootAppState extends State<NutriSnapRootApp> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _SessionState _sessionState = _SessionState.loading;
  _AuthMode _authMode = _AuthMode.signIn;

  bool _isSubmitting = false;
  bool _isResendingVerification = false;
  bool _emailVerified = false;
  bool _hasCompletedOnboarding = false;

  String? _authError;
  String? _authSuccess;

  @override
  void initState() {
    super.initState();
    _bootstrapSession();
  }

  Future<void> _bootstrapSession() async {
    // TODO: replace with Firebase auth stream + profile hydration.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _sessionState = _SessionState.signedOut);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'auth/user-not-found':
        return 'No account found with this email.';
      case 'auth/wrong-password':
        return 'Incorrect password. Please try again.';
      case 'auth/email-already-in-use':
        return 'An account already exists with this email.';
      case 'auth/weak-password':
        return 'Password should be at least 6 characters.';
      case 'auth/invalid-email':
        return 'Please enter a valid email address.';
      case 'auth/too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'auth/network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }

  Future<void> _handleEmailAuth() async {
    if (_emailController.text.trim().isEmpty ||
        (_authMode != _AuthMode.forgotPassword &&
            _passwordController.text.trim().isEmpty)) {
      setState(() => _authError = 'Please fill in all required fields.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _authError = null;
      _authSuccess = null;
    });

    // TODO: replace with Firebase Auth calls.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    switch (_authMode) {
      case _AuthMode.signIn:
        setState(() {
          _sessionState = _SessionState.signedIn;
          _isSubmitting = false;
        });
        break;
      case _AuthMode.signUp:
        setState(() {
          _authSuccess =
              'Account created! Please check your email for a verification link.';
          _isSubmitting = false;
          _emailVerified = false;
        });
        break;
      case _AuthMode.forgotPassword:
        setState(() {
          _authSuccess = 'Password reset link sent to your email!';
          _isSubmitting = false;
        });
        break;
    }
  }

  Future<void> _signInWithProvider(String provider) async {
    setState(() {
      _isSubmitting = true;
      _authError = null;
      _authSuccess = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    if (provider == 'github') {
      // Simulate occasional provider fallback to show mapped errors.
      setState(() {
        _authError = _friendlyError('auth/cancelled-popup-request');
        _isSubmitting = false;
      });
      return;
    }

    setState(() {
      _sessionState = _SessionState.signedIn;
      _isSubmitting = false;
    });
  }

  Future<void> _resendVerification() async {
    setState(() {
      _isResendingVerification = true;
      _authError = null;
      _authSuccess = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    setState(() {
      _isResendingVerification = false;
      _authSuccess = 'Verification email resent!';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: switch (_sessionState) {
        _SessionState.loading => const _LoadingScreen(),
        _SessionState.signedOut => _AuthScreen(
            key: const ValueKey('auth'),
            emailController: _emailController,
            passwordController: _passwordController,
            authMode: _authMode,
            isSubmitting: _isSubmitting,
            authError: _authError,
            authSuccess: _authSuccess,
            onGoogleTap: () => _signInWithProvider('google'),
            onGitHubTap: () => _signInWithProvider('github'),
            onSubmit: _handleEmailAuth,
            onSwitchAuthMode: () {
              setState(() {
                _authError = null;
                _authSuccess = null;
                _authMode = _authMode == _AuthMode.signIn
                    ? _AuthMode.signUp
                    : _AuthMode.signIn;
              });
            },
            onForgotPassword: () {
              setState(() {
                _authError = null;
                _authSuccess = null;
                _authMode = _AuthMode.forgotPassword;
              });
            },
            onBackToLogin: () {
              setState(() {
                _authError = null;
                _authSuccess = null;
                _authMode = _AuthMode.signIn;
              });
            },
          ),
        _SessionState.signedIn => _MainGate(
            key: const ValueKey('main'),
            hasCompletedOnboarding: _hasCompletedOnboarding,
            emailVerified: _emailVerified,
            isResendingVerification: _isResendingVerification,
            onResendVerification: _resendVerification,
          ),
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AuthScreen extends StatelessWidget {
  const _AuthScreen({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.authMode,
    required this.isSubmitting,
    required this.authError,
    required this.authSuccess,
    required this.onGoogleTap,
    required this.onGitHubTap,
    required this.onSubmit,
    required this.onSwitchAuthMode,
    required this.onForgotPassword,
    required this.onBackToLogin,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final _AuthMode authMode;
  final bool isSubmitting;
  final String? authError;
  final String? authSuccess;
  final VoidCallback onGoogleTap;
  final VoidCallback onGitHubTap;
  final VoidCallback onSubmit;
  final VoidCallback onSwitchAuthMode;
  final VoidCallback onForgotPassword;
  final VoidCallback onBackToLogin;

  bool get _isForgotPassword => authMode == _AuthMode.forgotPassword;
  bool get _isSignUp => authMode == _AuthMode.signUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GlassSurface(
                radius: 32,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'NutriSnap AI',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration:
                          const InputDecoration(hintText: 'Email Address'),
                    ),
                    if (!_isForgotPassword) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(hintText: 'Password'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: isSubmitting ? null : onSubmit,
                      child: Text(
                        _isForgotPassword
                            ? 'Send Reset Link'
                            : _isSignUp
                                ? 'Create Account'
                                : 'Sign In',
                      ),
                    ),
                    if (!_isForgotPassword) ...[
                      TextButton(
                        onPressed: isSubmitting ? null : onForgotPassword,
                        child: const Text('Forgot Password?'),
                      ),
                      Row(
                        children: const [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('Or continue with'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSubmitting ? null : onGoogleTap,
                              child: const Text('Google'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.tonal(
                              onPressed: isSubmitting ? null : onGitHubTap,
                              child: const Text('GitHub'),
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: isSubmitting ? null : onSwitchAuthMode,
                        child: Text(_isSignUp
                            ? 'Already have an account? Sign In'
                            : 'Don\'t have an account? Sign Up'),
                      ),
                    ],
                    if (_isForgotPassword)
                      TextButton(
                        onPressed: isSubmitting ? null : onBackToLogin,
                        child: const Text('Back to Login'),
                      ),
                    if (authError != null) ...[
                      const SizedBox(height: 8),
                      _MessagePill(text: authError!, isError: true),
                    ],
                    if (authSuccess != null) ...[
                      const SizedBox(height: 8),
                      _MessagePill(text: authSuccess!, isError: false),
                    ],
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

class _MainGate extends StatelessWidget {
  const _MainGate({
    super.key,
    required this.hasCompletedOnboarding,
    required this.emailVerified,
    required this.isResendingVerification,
    required this.onResendVerification,
  });

  final bool hasCompletedOnboarding;
  final bool emailVerified;
  final bool isResendingVerification;
  final VoidCallback onResendVerification;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (!emailVerified)
            Material(
              color: const Color(0xFFFFFBEB),
              child: ListTile(
                leading: const Icon(Icons.mail_outline, color: Color(0xFFB45309)),
                title: const Text('Email not verified'),
                subtitle: const Text('Please verify your email to secure your account.'),
                trailing: FilledButton(
                  onPressed: isResendingVerification ? null : onResendVerification,
                  child: Text(isResendingVerification ? 'Sending...' : 'Resend Link'),
                ),
              ),
            ),
          Expanded(
            child: hasCompletedOnboarding
                ? const _PlaceholderScreen(title: 'Main App Layout')
                : const _PlaceholderScreen(title: 'Onboarding Screen'),
          ),
        ],
      ),
    );
  }
}

class _MessagePill extends StatelessWidget {
  const _MessagePill({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFEF4444) : const Color(0xFF16A34A);
    final bg = isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Source conversion is in progress for this module.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
