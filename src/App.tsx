import React, { useState, useEffect, Component, ErrorInfo, ReactNode } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { 
  onAuthStateChanged, 
  signInWithPopup, 
  GoogleAuthProvider, 
  GithubAuthProvider,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  sendEmailVerification,
  sendPasswordResetEmail,
  User 
} from 'firebase/auth';
import { auth } from './firebase';
import { triggerHaptic, hapticPatterns } from './lib/haptics';
import { LogIn, Sparkles, Github, Mail, Lock, User as UserIcon, ArrowRight, AlertCircle, CheckCircle2, RefreshCw } from 'lucide-react';
import Layout from './components/Layout';
import HomeScreen from './screens/HomeScreen';
import HistoryScreen from './screens/HistoryScreen';
import AnalyticsScreen from './screens/AnalyticsScreen';
import AIChatScreen from './screens/AIChatScreen';
import SettingsScreen from './screens/SettingsScreen';
import ResultScreen from './screens/ResultScreen';
import OnboardingScreen from './screens/OnboardingScreen';

// Error Boundary Component
class ErrorBoundary extends Component<{ children: ReactNode }, { hasError: boolean, error: any }> {
  constructor(props: { children: ReactNode }) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: any) {
    return { hasError: true, error };
  }

  componentDidCatch(error: any, errorInfo: ErrorInfo) {
    console.error("ErrorBoundary caught an error", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex flex-col items-center justify-center min-h-screen p-8 text-center bg-[#F7F8FA]">
          <div className="w-20 h-20 bg-red-100 text-red-600 rounded-full flex items-center justify-center mb-6">
            <span className="text-4xl font-bold">!</span>
          </div>
          <h1 className="text-2xl font-bold text-gray-900 mb-2">Something went wrong</h1>
          <p className="text-gray-500 mb-8 max-w-xs mx-auto">
            We encountered an unexpected error. Please try refreshing the app.
          </p>
          <button 
            onClick={() => window.location.reload()}
            className="bg-green-600 text-white px-8 py-3 rounded-2xl font-bold shadow-lg hover:bg-green-700 transition-all"
          >
            Refresh App
          </button>
          {process.env.NODE_ENV === 'development' && (
            <pre className="mt-8 p-4 bg-gray-800 text-red-400 text-xs text-left rounded-xl overflow-auto max-w-full">
              {this.state.error?.toString()}
            </pre>
          )}
        </div>
      );
    }

    return this.props.children;
  }
}

import { UserProvider, useUser } from './contexts/UserContext';
import { requestNotificationPermission } from './lib/notifications';

const AppContent: React.FC = () => {
  const { user, profile, loading } = useUser();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isSignUp, setIsSignUp] = useState(false);
  const [isForgotPassword, setIsForgotPassword] = useState(false);
  const [authError, setAuthError] = useState<string | null>(null);
  const [authSuccess, setAuthSuccess] = useState<string | null>(null);
  const [isVerifying, setIsVerifying] = useState(false);

  useEffect(() => {
    // Request notification permission
    requestNotificationPermission();
  }, []);

  const getFriendlyErrorMessage = (errorCode: string) => {
    switch (errorCode) {
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
      case 'auth/popup-closed-by-user':
        return 'Login cancelled. Please keep the window open to sign in.';
      case 'auth/cancelled-popup-request':
        return 'Login request was cancelled. Please try again.';
      case 'auth/unauthorized-domain':
        return 'This domain is not authorized for login. Please check your Firebase settings.';
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  };

  const handleGoogleLogin = async () => {
    triggerHaptic(hapticPatterns.medium);
    setAuthError(null);
    const provider = new GoogleAuthProvider();
    try {
      await signInWithPopup(auth, provider);
      triggerHaptic(hapticPatterns.success);
    } catch (error: any) {
      triggerHaptic(hapticPatterns.error);
      setAuthError(getFriendlyErrorMessage(error.code));
      console.error("Google login failed", error);
    }
  };

  const handleGithubLogin = async () => {
    triggerHaptic(hapticPatterns.medium);
    setAuthError(null);
    const provider = new GithubAuthProvider();
    // Add scopes that might be needed for some GitHub accounts
    provider.addScope('read:user');
    provider.addScope('user:email');
    
    try {
      await signInWithPopup(auth, provider);
      triggerHaptic(hapticPatterns.success);
    } catch (error: any) {
      triggerHaptic(hapticPatterns.error);
      const friendlyMessage = getFriendlyErrorMessage(error.code);
      setAuthError(friendlyMessage);
      
      // Detailed logging for the user to see in the console
      console.group("GitHub Login Debug Info");
      console.error("Error Code:", error.code);
      console.error("Error Message:", error.message);
      console.error("Full Error Object:", error);
      console.info("Check if your App URL is allowlisted in Firebase Console > Authentication > Settings > Authorized domains");
      console.info("Check if GitHub callback URL is set to: https://gen-lang-client-0654629425.firebaseapp.com/__/auth/handler");
      console.groupEnd();
    }
  };

  const handleEmailAuth = async (e: React.FormEvent) => {
    e.preventDefault();
    triggerHaptic(hapticPatterns.medium);
    setAuthError(null);
    setAuthSuccess(null);
    
    try {
      if (isSignUp) {
        const userCredential = await createUserWithEmailAndPassword(auth, email, password);
        await sendEmailVerification(userCredential.user);
        setAuthSuccess('Account created! Please check your email for a verification link.');
      } else {
        await signInWithEmailAndPassword(auth, email, password);
      }
      triggerHaptic(hapticPatterns.success);
    } catch (error: any) {
      triggerHaptic(hapticPatterns.error);
      setAuthError(getFriendlyErrorMessage(error.code));
      console.error("Email auth failed", error);
    }
  };

  const handleForgotPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    triggerHaptic(hapticPatterns.medium);
    setAuthError(null);
    setAuthSuccess(null);

    try {
      await sendPasswordResetEmail(auth, email);
      setAuthSuccess('Password reset link sent to your email!');
      triggerHaptic(hapticPatterns.success);
    } catch (error: any) {
      triggerHaptic(hapticPatterns.error);
      setAuthError(getFriendlyErrorMessage(error.code));
    }
  };

  const resendVerification = async () => {
    if (user && !user.emailVerified) {
      setIsVerifying(true);
      try {
        await sendEmailVerification(user);
        setAuthSuccess('Verification email resent!');
        triggerHaptic(hapticPatterns.success);
      } catch (error: any) {
        setAuthError(getFriendlyErrorMessage(error.code));
        triggerHaptic(hapticPatterns.error);
      } finally {
        setIsVerifying(false);
      }
    }
  };

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen bg-[#F7F8FA]">
        <div className="relative">
          <div className="w-20 h-20 border-4 border-green-500/20 rounded-[32px] absolute inset-0" />
          <div className="w-20 h-20 border-4 border-green-500 border-t-transparent rounded-[32px] animate-spin" />
        </div>
        <p className="mt-8 text-gray-400 font-bold tracking-widest uppercase text-[10px] animate-pulse">NutriSnap AI is loading</p>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen bg-[#F7F8FA] p-6 text-center relative overflow-hidden">
        {/* Background Accents */}
        <div className="absolute top-[-10%] right-[-10%] w-[60%] h-[40%] bg-green-500/5 blur-[120px] rounded-full" />
        <div className="absolute bottom-[-10%] left-[-10%] w-[60%] h-[40%] bg-blue-500/5 blur-[120px] rounded-full" />

        <div className="relative z-10 space-y-8 w-full max-w-sm">
          <div className="flex flex-col items-center space-y-4">
            <div className="w-20 h-20 bg-green-500 rounded-[32px] flex items-center justify-center text-white shadow-2xl shadow-green-500/30 ios-shadow transform hover:scale-105 transition-transform">
              <Sparkles size={40} strokeWidth={1.5} />
            </div>
            <div className="space-y-1">
              <h1 className="text-3xl font-black text-gray-900 tracking-tighter">NutriSnap AI</h1>
              <p className="text-[10px] text-gray-400 font-bold uppercase tracking-[0.2em]">Your Personal Nutritionist</p>
            </div>
          </div>

          <div className="bg-white p-8 rounded-[32px] shadow-xl shadow-gray-200/50 space-y-6 border border-gray-100">
            {isForgotPassword ? (
              <form onSubmit={handleForgotPassword} className="space-y-4">
                <div className="space-y-2">
                  <h2 className="text-xl font-bold text-gray-900">Reset Password</h2>
                  <p className="text-sm text-gray-500">Enter your email to receive a reset link.</p>
                  <div className="relative">
                    <Mail className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400" size={18} />
                    <input 
                      type="email" 
                      placeholder="Email Address"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      required
                      className="w-full bg-gray-50 border-none rounded-2xl py-4 pl-12 pr-4 text-sm font-medium focus:ring-2 focus:ring-green-500 transition-all"
                    />
                  </div>
                </div>

                {authError && (
                  <div className="flex items-center gap-2 text-xs text-red-500 font-bold bg-red-50 p-3 rounded-xl">
                    <AlertCircle size={14} />
                    {authError}
                  </div>
                )}

                {authSuccess && (
                  <div className="flex items-center gap-2 text-xs text-green-600 font-bold bg-green-50 p-3 rounded-xl">
                    <CheckCircle2 size={14} />
                    {authSuccess}
                  </div>
                )}

                <button 
                  type="submit"
                  className="w-full bg-green-600 text-white py-4 rounded-2xl font-black shadow-lg shadow-green-600/20 hover:bg-green-700 transition-all flex items-center justify-center gap-2 active:scale-[0.98]"
                >
                  Send Reset Link
                  <ArrowRight size={18} />
                </button>

                <button 
                  type="button"
                  onClick={() => { setIsForgotPassword(false); setAuthError(null); setAuthSuccess(null); }}
                  className="w-full text-xs font-bold text-gray-400 hover:text-gray-600 transition-colors"
                >
                  Back to Login
                </button>
              </form>
            ) : (
              <form onSubmit={handleEmailAuth} className="space-y-4">
                <div className="space-y-2">
                  <div className="relative">
                    <Mail className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400" size={18} />
                    <input 
                      type="email" 
                      placeholder="Email Address"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      required
                      className="w-full bg-gray-50 border-none rounded-2xl py-4 pl-12 pr-4 text-sm font-medium focus:ring-2 focus:ring-green-500 transition-all"
                    />
                  </div>
                  <div className="relative">
                    <Lock className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400" size={18} />
                    <input 
                      type="password" 
                      placeholder="Password"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      required
                      className="w-full bg-gray-50 border-none rounded-2xl py-4 pl-12 pr-4 text-sm font-medium focus:ring-2 focus:ring-green-500 transition-all"
                    />
                  </div>
                </div>

                <div className="flex justify-end">
                  <button 
                    type="button"
                    onClick={() => { setIsForgotPassword(true); setAuthError(null); setAuthSuccess(null); }}
                    className="text-xs font-bold text-green-600 hover:text-green-700 transition-colors"
                  >
                    Forgot Password?
                  </button>
                </div>

                {authError && (
                  <div className="flex items-center gap-2 text-xs text-red-500 font-bold bg-red-50 p-3 rounded-xl">
                    <AlertCircle size={14} />
                    {authError}
                  </div>
                )}

                {authSuccess && (
                  <div className="flex items-center gap-2 text-xs text-green-600 font-bold bg-green-50 p-3 rounded-xl">
                    <CheckCircle2 size={14} />
                    {authSuccess}
                  </div>
                )}

                <button 
                  type="submit"
                  className="w-full bg-green-600 text-white py-4 rounded-2xl font-black shadow-lg shadow-green-600/20 hover:bg-green-700 transition-all flex items-center justify-center gap-2 active:scale-[0.98]"
                >
                  {isSignUp ? 'Create Account' : 'Sign In'}
                  <ArrowRight size={18} />
                </button>
              </form>
            )}

            {!isForgotPassword && (
              <>
                <div className="relative">
                  <div className="absolute inset-0 flex items-center">
                    <div className="w-full border-t border-gray-100"></div>
                  </div>
                  <div className="relative flex justify-center text-[10px] uppercase tracking-widest font-bold text-gray-400">
                    <span className="bg-white px-4">Or continue with</span>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <button 
                    onClick={handleGoogleLogin}
                    className="flex items-center justify-center gap-2 bg-gray-50 text-gray-900 py-4 rounded-2xl font-bold text-sm hover:bg-gray-100 transition-all active:scale-[0.98] border border-gray-100"
                  >
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                      <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
                      <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-1 .67-2.26 1.07-3.71 1.07-2.87 0-5.3-1.94-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
                      <path d="M5.84 14.11c-.22-.66-.35-1.36-.35-2.11s.13-1.45.35-2.11V7.05H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.95l3.66-2.84z" fill="#FBBC05"/>
                      <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.05l3.66 2.84c.86-2.59 3.3-4.51 6.16-4.51z" fill="#EA4335"/>
                    </svg>
                    Google
                  </button>
                  <button 
                    onClick={handleGithubLogin}
                    className="flex items-center justify-center gap-2 bg-gray-900 text-white py-4 rounded-2xl font-bold text-sm hover:bg-black transition-all active:scale-[0.98]"
                  >
                    <Github size={18} />
                    GitHub
                  </button>
                </div>

                <button 
                  onClick={() => { setIsSignUp(!isSignUp); setAuthError(null); setAuthSuccess(null); }}
                  className="w-full text-xs font-bold text-gray-500 hover:text-green-600 transition-colors"
                >
                  {isSignUp ? 'Already have an account? Sign In' : "Don't have an account? Sign Up"}
                </button>
              </>
            )}
          </div>

          <p className="text-[10px] text-gray-400 font-bold uppercase tracking-widest">
            By continuing, you agree to our Terms & Privacy
          </p>
        </div>
      </div>
    );
  }

  const hasCompletedOnboarding = profile?.hasCompletedOnboarding;

  return (
    <ErrorBoundary>
      <BrowserRouter>
        {user && !user.emailVerified && (
          <div className="bg-amber-50 border-b border-amber-100 px-6 py-3 flex items-center justify-between sticky top-0 z-[100]">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 bg-amber-100 text-amber-600 rounded-full flex items-center justify-center">
                <Mail size={16} />
              </div>
              <div>
                <p className="text-xs font-bold text-amber-900">Email not verified</p>
                <p className="text-[10px] text-amber-700 font-medium">Please verify your email to secure your account.</p>
              </div>
            </div>
            <button 
              onClick={resendVerification}
              disabled={isVerifying}
              className="bg-amber-600 text-white px-4 py-2 rounded-xl text-[10px] font-bold shadow-sm hover:bg-amber-700 transition-all disabled:opacity-50 flex items-center gap-2"
            >
              {isVerifying ? <RefreshCw size={12} className="animate-spin" /> : 'Resend Link'}
            </button>
          </div>
        )}
        <Routes>
          {!hasCompletedOnboarding ? (
            <>
              <Route path="/onboarding" element={<OnboardingScreen />} />
              <Route path="*" element={<Navigate to="/onboarding" replace />} />
            </>
          ) : (
            <>
              <Route path="/" element={<Layout />}>
                <Route index element={<HomeScreen />} />
                <Route path="history" element={<HistoryScreen />} />
                <Route path="analytics" element={<AnalyticsScreen />} />
                <Route path="chat" element={<AIChatScreen />} />
                <Route path="settings" element={<SettingsScreen />} />
                <Route path="result/:id" element={<ResultScreen />} />
              </Route>
              <Route path="/onboarding" element={<Navigate to="/" replace />} />
              <Route path="*" element={<Navigate to="/" replace />} />
            </>
          )}
        </Routes>
      </BrowserRouter>
    </ErrorBoundary>
  );
};

const App: React.FC = () => {
  return (
    <UserProvider>
      <AppContent />
    </UserProvider>
  );
};

export default App;
