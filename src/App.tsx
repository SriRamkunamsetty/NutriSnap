import React, { useState, useEffect, Component, ErrorInfo, ReactNode } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { onAuthStateChanged, signInWithPopup, GoogleAuthProvider, User } from 'firebase/auth';
import { auth } from './firebase';
import { triggerHaptic, hapticPatterns } from './lib/haptics';
import { LogIn, Sparkles } from 'lucide-react';
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

  useEffect(() => {
    // Request notification permission
    requestNotificationPermission();
  }, []);

  const handleLogin = async () => {
    triggerHaptic(hapticPatterns.medium);
    const provider = new GoogleAuthProvider();
    try {
      await signInWithPopup(auth, provider);
      triggerHaptic(hapticPatterns.success);
    } catch (error) {
      triggerHaptic(hapticPatterns.error);
      console.error("Login failed", error);
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
      <div className="flex flex-col items-center justify-center min-h-screen bg-[#F7F8FA] p-10 text-center relative overflow-hidden">
        {/* Background Accents */}
        <div className="absolute top-[-10%] right-[-10%] w-[60%] h-[40%] bg-green-500/5 blur-[120px] rounded-full" />
        <div className="absolute bottom-[-10%] left-[-10%] w-[60%] h-[40%] bg-blue-500/5 blur-[120px] rounded-full" />

        <div className="relative z-10 space-y-12 max-w-sm">
          <div className="flex flex-col items-center space-y-6">
            <div className="w-28 h-28 bg-green-500 rounded-[40px] flex items-center justify-center text-white shadow-2xl shadow-green-500/30 ios-shadow transform hover:scale-105 transition-transform">
              <Sparkles size={56} strokeWidth={1.5} />
            </div>
            <div className="space-y-2">
              <h1 className="text-4xl font-black text-gray-900 tracking-tighter">NutriSnap AI</h1>
              <p className="text-sm text-gray-400 font-bold uppercase tracking-[0.2em]">Your Personal Nutritionist</p>
            </div>
          </div>

          <p className="text-gray-500 leading-relaxed font-medium text-lg">
            Scan your meals, track your progress, and reach your fitness goals with the power of AI.
          </p>

          <div className="space-y-4">
            <button 
              onClick={handleLogin}
              className="w-full bg-gray-900 text-white py-5 rounded-[28px] font-black shadow-2xl hover:bg-black transition-all flex items-center justify-center gap-4 active:scale-[0.98] ios-shadow"
            >
              <LogIn size={20} strokeWidth={2.5} />
              Continue with Google
            </button>
            <p className="text-[10px] text-gray-400 font-bold uppercase tracking-widest">
              By continuing, you agree to our Terms & Privacy
            </p>
          </div>
        </div>
      </div>
    );
  }

  const hasCompletedOnboarding = profile?.hasCompletedOnboarding;

  return (
    <ErrorBoundary>
      <BrowserRouter>
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
