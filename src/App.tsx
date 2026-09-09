import React, { useState, useEffect, Component, ErrorInfo, ReactNode } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { triggerHaptic, hapticPatterns } from './lib/haptics';
import { Sparkles, Mail, User as UserIcon, ArrowRight, ShieldCheck, CheckCircle2, Lock } from 'lucide-react';
import Layout from './components/Layout';
import HomeScreen from './screens/HomeScreen';
import HistoryScreen from './screens/HistoryScreen';
import AnalyticsScreen from './screens/AnalyticsScreen';
import AIChatScreen from './screens/AIChatScreen';
import SettingsScreen from './screens/SettingsScreen';
import ResultScreen from './screens/ResultScreen';
import OnboardingScreen from './screens/OnboardingScreen';
import { UserProvider, useUser } from './contexts/UserContext';
import { requestNotificationPermission } from './lib/notifications';
import { AppUser } from './types';

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

const AppContent: React.FC = () => {
  const { user, profile, loading, login } = useUser();
  const [displayName, setDisplayName] = useState('');
  const [email, setEmail] = useState('');
  const [showProfileSetup, setShowProfileSetup] = useState(false);

  useEffect(() => {
    // Request notification permission
    requestNotificationPermission();
  }, []);

  const handleStartOnDeviceSession = (e: React.FormEvent) => {
    e.preventDefault();
    triggerHaptic(hapticPatterns.success);

    const newUser: AppUser = {
      uid: `local_user_${Date.now()}`,
      email: email.trim() || 'private.user@on-device.local',
      displayName: displayName.trim() || 'NutriSnap User',
      photoURL: '',
    };
    login(newUser);
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

  // If no user exists yet or user wants to customize profile login
  if (!user && showProfileSetup) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen bg-[#F7F8FA] p-6 text-center relative overflow-hidden">
        <div className="absolute top-[-10%] right-[-10%] w-[60%] h-[40%] bg-green-500/5 blur-[120px] rounded-full" />
        <div className="absolute bottom-[-10%] left-[-10%] w-[60%] h-[40%] bg-blue-500/5 blur-[120px] rounded-full" />

        <div className="relative z-10 space-y-6 w-full max-w-sm">
          <div className="flex flex-col items-center space-y-4">
            <div className="w-20 h-20 bg-green-500 rounded-[32px] flex items-center justify-center text-white shadow-2xl shadow-green-500/30 ios-shadow">
              <Sparkles size={40} strokeWidth={1.5} />
            </div>
            <div className="space-y-1">
              <h1 className="text-3xl font-black text-gray-900 tracking-tighter">NutriSnap AI</h1>
              <p className="text-[10px] text-gray-400 font-bold uppercase tracking-[0.2em]">100% Private On-Device Health</p>
            </div>
          </div>

          <div className="bg-white p-8 rounded-[32px] shadow-xl shadow-gray-200/50 space-y-6 border border-gray-100 text-left">
            <div className="space-y-1 text-center">
              <h2 className="text-xl font-bold text-gray-900">Create Private Profile</h2>
              <p className="text-xs text-gray-500">Stored exclusively on your device. Zero cloud sync.</p>
            </div>

            <form onSubmit={handleStartOnDeviceSession} className="space-y-4">
              <div className="space-y-3">
                <div className="relative">
                  <UserIcon className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400" size={18} />
                  <input 
                    type="text" 
                    placeholder="Your Name (e.g. Alex)"
                    value={displayName}
                    onChange={(e) => setDisplayName(e.target.value)}
                    className="w-full bg-gray-50 border-none rounded-2xl py-4 pl-12 pr-4 text-sm font-medium focus:ring-2 focus:ring-green-500 transition-all"
                  />
                </div>

                <div className="relative">
                  <Mail className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400" size={18} />
                  <input 
                    type="email" 
                    placeholder="Email (optional, for local reference)"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="w-full bg-gray-50 border-none rounded-2xl py-4 pl-12 pr-4 text-sm font-medium focus:ring-2 focus:ring-green-500 transition-all"
                  />
                </div>
              </div>

              <div className="p-3 bg-emerald-50 rounded-2xl border border-emerald-100 flex items-start gap-2.5">
                <ShieldCheck size={18} className="text-emerald-600 shrink-0 mt-0.5" />
                <p className="text-xs text-emerald-800 leading-relaxed font-medium">
                  Your meals, calories, and photos are encrypted and kept 100% on your device.
                </p>
              </div>

              <button 
                type="submit"
                className="w-full bg-green-600 text-white py-4 rounded-2xl font-black shadow-lg shadow-green-600/20 hover:bg-green-700 transition-all flex items-center justify-center gap-2 active:scale-[0.98]"
              >
                <span>Enter Private App</span>
                <ArrowRight size={18} />
              </button>
            </form>
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
