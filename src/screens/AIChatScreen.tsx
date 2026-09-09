import React, { useState, useRef, useEffect } from 'react';
import { Send, Sparkles, User, Bot, Loader2, Info, MessageSquare, Lock, ArrowRight, ShieldCheck, Zap, Utensils } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { getAICoachResponse } from '../services/geminiService';
import { saveChatMessage, getChatHistory, getDailySummaryOnce } from '../services/storageService';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { useUser } from '../contexts/UserContext';
import ReactMarkdown from 'react-markdown';
import { ChatMessage } from '../types';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const AIChatScreen: React.FC = () => {
  const { user, profile, scans, dailySummary, refreshProfile, login } = useUser();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [suggestions, setSuggestions] = useState<string[]>([]);
  const scrollRef = useRef<HTMLDivElement>(null);

  // Auth unlock modal state for guest users
  const [showSignInModal, setShowSignInModal] = useState(false);
  const [signInName, setSignInName] = useState('');
  const [signInEmail, setSignInEmail] = useState('');

  const isGuest = !user || user.isGuest || user.email.includes('guest');

  useEffect(() => {
    if (isGuest) return;

    const unsubscribe = getChatHistory((history) => {
      if (history.length === 0) {
        // Initial personalized greeting
        const greeting: ChatMessage = {
          id: 'greeting',
          userId: profile?.uid || 'system',
          role: 'model',
          text: `Hi ${profile?.displayName?.split(' ')[0] || 'there'}! I'm your NutriSnap AI coach. I have your current metrics (${dailySummary?.totalCalories || 0} kcal consumed today, ${dailySummary?.totalWater || 0}ml water). How can I guide your nutrition right now?`,
          timestamp: new Date().toISOString()
        };
        setMessages([greeting]);
      } else {
        setMessages(history);
      }
    });
    return () => unsubscribe();
  }, [profile, isGuest, dailySummary]);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, isLoading, suggestions]);

  const handleSend = async (textToSend?: string) => {
    if (isGuest) {
      setShowSignInModal(true);
      return;
    }

    const messageText = textToSend || input.trim();
    if (!messageText || isLoading) return;

    if (!textToSend) setInput('');
    setSuggestions([]);
    setIsLoading(true);
    triggerHaptic(hapticPatterns.medium);

    try {
      const [latestProfile, latestSummary] = await Promise.all([
        refreshProfile(),
        getDailySummaryOnce()
      ]);
      
      const currentProfile = latestProfile || profile;
      const currentSummary = latestSummary || dailySummary;
      
      await saveChatMessage('user', messageText);
      const result = await getAICoachResponse(
        [...messages, { role: 'user', text: messageText } as any].map(m => ({ role: m.role, text: m.text })),
        currentProfile,
        currentSummary,
        scans
      );
      
      if (result && result.text) {
        await saveChatMessage('model', result.text);
        setSuggestions(result.suggestions || []);
        triggerHaptic(hapticPatterns.success);
      }
    } catch (error) {
      console.error("Chat failed", error);
      triggerHaptic(hapticPatterns.error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleQuickSignIn = (e: React.FormEvent) => {
    e.preventDefault();
    const name = signInName.trim() || 'Health Champion';
    const email = signInEmail.trim() || 'user@nutrisnap.local';

    login({
      uid: `user_${Date.now()}`,
      displayName: name,
      email: email,
      isGuest: false,
    });
    setShowSignInModal(false);
    triggerHaptic(hapticPatterns.success);
  };

  // Phase 1 Bug 1: Beautiful Sign-In to Unlock screen for guests
  if (isGuest) {
    return (
      <div className="flex flex-col h-full bg-transparent px-6 py-8 justify-between overflow-y-auto">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-emerald-500/10 rounded-2xl flex items-center justify-center text-emerald-600">
              <Bot size={22} strokeWidth={2.5} />
            </div>
            <div>
              <h2 className="text-xl font-bold text-gray-900 tracking-tight">AI Nutrition Coach</h2>
              <p className="text-xs font-semibold text-emerald-600 uppercase tracking-wider">Members Only</p>
            </div>
          </div>
          <span className="text-xs font-bold text-gray-400 glass px-3 py-1.5 rounded-full border border-gray-100 flex items-center gap-1.5">
            <Lock size={12} /> Locked
          </span>
        </div>

        {/* Hero Card */}
        <motion.div 
          initial={{ opacity: 0, y: 15 }}
          animate={{ opacity: 1, y: 0 }}
          className="my-auto py-6"
        >
          <div className="glass-card rounded-[32px] p-8 border border-white/60 shadow-xl relative overflow-hidden text-center space-y-6">
            <div className="w-20 h-20 bg-gradient-to-tr from-emerald-500 to-teal-400 rounded-3xl mx-auto flex items-center justify-center text-white shadow-xl shadow-emerald-500/20">
              <Sparkles size={36} />
            </div>

            <div className="space-y-2">
              <h3 className="text-2xl font-black text-gray-900 tracking-tight">
                Sign In to Unlock AI Coach
              </h3>
              <p className="text-sm text-gray-500 leading-relaxed max-w-sm mx-auto">
                Get real-time answers calibrated to your current calories, protein deficit, water intake, and personal food logs.
              </p>
            </div>

            <div className="space-y-3 text-left pt-2">
              <div className="flex items-center gap-3.5 p-3 rounded-2xl bg-white/70 border border-emerald-100/50">
                <div className="w-8 h-8 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center shrink-0">
                  <Zap size={18} />
                </div>
                <div>
                  <h4 className="text-xs font-bold text-gray-800">Dynamic Daily Macro Guidance</h4>
                  <p className="text-[11px] text-gray-500">Know what to eat based on exact remaining calories</p>
                </div>
              </div>

              <div className="flex items-center gap-3.5 p-3 rounded-2xl bg-white/70 border border-emerald-100/50">
                <div className="w-8 h-8 rounded-xl bg-teal-50 text-teal-600 flex items-center justify-center shrink-0">
                  <Utensils size={18} />
                </div>
                <div>
                  <h4 className="text-xs font-bold text-gray-800">MessOS & Dining Out Hacks</h4>
                  <p className="text-[11px] text-gray-500">Tailored suggestions for hostel food, cafes & regional diets</p>
                </div>
              </div>

              <div className="flex items-center gap-3.5 p-3 rounded-2xl bg-white/70 border border-emerald-100/50">
                <div className="w-8 h-8 rounded-xl bg-purple-50 text-purple-600 flex items-center justify-center shrink-0">
                  <ShieldCheck size={18} />
                </div>
                <div>
                  <h4 className="text-xs font-bold text-gray-800">100% On-Device & Private</h4>
                  <p className="text-[11px] text-gray-500">Zero cloud database tracking, local encrypted history</p>
                </div>
              </div>
            </div>

            <button
              onClick={() => setShowSignInModal(true)}
              className="w-full py-4 bg-emerald-600 hover:bg-emerald-700 text-white rounded-2xl font-bold shadow-lg shadow-emerald-600/25 flex items-center justify-center gap-2 transition-all"
            >
              <span>Sign In / Create Account</span>
              <ArrowRight size={18} />
            </button>
          </div>
        </motion.div>

        {/* Quick Modal */}
        <AnimatePresence>
          {showSignInModal && (
            <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-sm flex items-end sm:items-center justify-center p-4">
              <motion.div
                initial={{ opacity: 0, y: 30 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: 30 }}
                className="bg-white rounded-[32px] w-full max-w-md p-6 shadow-2xl border border-gray-100"
              >
                <div className="flex justify-between items-center pb-4 border-b border-gray-100">
                  <div>
                    <h3 className="text-lg font-bold text-gray-900">Sign In to NutriSnap</h3>
                    <p className="text-xs text-gray-500">Unlocks AI Coach & personal health sync</p>
                  </div>
                  <button 
                    onClick={() => setShowSignInModal(false)}
                    className="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-500"
                  >
                    ✕
                  </button>
                </div>

                <form onSubmit={handleQuickSignIn} className="space-y-4 pt-4">
                  <div>
                    <label className="text-xs font-bold text-gray-600 uppercase tracking-wider block mb-1.5">
                      Your Name
                    </label>
                    <input
                      type="text"
                      required
                      placeholder="e.g. Alex Miller"
                      value={signInName}
                      onChange={(e) => setSignInName(e.target.value)}
                      className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 text-sm font-medium"
                    />
                  </div>

                  <div>
                    <label className="text-xs font-bold text-gray-600 uppercase tracking-wider block mb-1.5">
                      Email Address
                    </label>
                    <input
                      type="email"
                      required
                      placeholder="alex@example.com"
                      value={signInEmail}
                      onChange={(e) => setSignInEmail(e.target.value)}
                      className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 text-sm font-medium"
                    />
                  </div>

                  <div className="pt-2">
                    <button
                      type="submit"
                      className="w-full py-3.5 bg-emerald-600 hover:bg-emerald-700 text-white font-bold rounded-xl shadow-md transition-all flex items-center justify-center gap-2"
                    >
                      <span>Unlock AI Coach</span>
                      <ArrowRight size={16} />
                    </button>
                  </div>
                </form>
              </motion.div>
            </div>
          )}
        </AnimatePresence>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full bg-transparent overflow-hidden">
      {/* Header */}
      <div className="px-6 py-4 flex items-center justify-between border-b border-gray-100/50 bg-white/40 backdrop-blur-md">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-emerald-500/10 rounded-2xl flex items-center justify-center text-emerald-600">
            <Bot size={22} strokeWidth={2.5} />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-base font-bold text-gray-900 tracking-tight">NutriSnap AI Coach</h2>
              <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
            </div>
            <p className="text-[11px] font-semibold text-emerald-600">Real-Time On-Device Guidance</p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <span className="text-[11px] font-bold text-gray-500 glass px-3 py-1 rounded-full border border-gray-100">
            {profile?.calorieLimit ? `${dailySummary?.totalCalories || 0} / ${profile.calorieLimit} kcal` : 'Calibrated'}
          </span>
        </div>
      </div>

      {/* Messages */}
      <div 
        ref={scrollRef}
        className="flex-1 overflow-y-auto px-6 py-4 space-y-4"
      >
        {messages.map((msg) => (
          <motion.div
            key={msg.id}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className={`flex gap-3 ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}
          >
            {msg.role === 'model' && (
              <div className="w-8 h-8 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center shrink-0 self-end">
                <Bot size={18} />
              </div>
            )}
            <div className={`max-w-[85%] ${msg.role === 'user' ? 'items-end' : 'items-start'} flex flex-col`}>
              <div className={`p-4 rounded-3xl text-sm ${
                msg.role === 'user' 
                  ? 'bg-emerald-600 text-white rounded-br-none shadow-md shadow-emerald-600/10' 
                  : 'bg-white text-gray-800 rounded-bl-none shadow-sm border border-gray-100'
              }`}>
                <div className="prose prose-sm max-w-none text-current">
                  <ReactMarkdown>{msg.text}</ReactMarkdown>
                </div>
              </div>
              <span className="text-[10px] font-semibold text-gray-400 mt-1 px-1">
                {new Date(msg.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </span>
            </div>
          </motion.div>
        ))}

        {isLoading && (
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center">
              <Bot size={18} />
            </div>
            <div className="px-5 py-3 rounded-2xl bg-white border border-gray-100 flex items-center gap-1.5">
              <div className="w-2 h-2 bg-emerald-500 rounded-full animate-bounce" />
              <div className="w-2 h-2 bg-emerald-500 rounded-full animate-bounce [animation-delay:0.2s]" />
              <div className="w-2 h-2 bg-emerald-500 rounded-full animate-bounce [animation-delay:0.4s]" />
            </div>
          </motion.div>
        )}

        {/* Suggestion Chips */}
        {!isLoading && suggestions.length > 0 && (
          <div className="flex flex-wrap gap-2 pt-2">
            {suggestions.map((s, idx) => (
              <button
                key={idx}
                onClick={() => handleSend(s)}
                className="px-3.5 py-1.5 rounded-full bg-emerald-50 hover:bg-emerald-100 text-emerald-700 text-xs font-semibold border border-emerald-200/60 flex items-center gap-1.5 transition-colors"
              >
                <MessageSquare size={12} />
                <span>{s}</span>
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Input */}
      <div className="p-4 bg-white/60 backdrop-blur-md border-t border-gray-100">
        <form 
          onSubmit={(e) => { e.preventDefault(); handleSend(); }}
          className="flex items-center gap-2"
        >
          <input
            type="text"
            placeholder="Ask anything about meals, macros, or mess food..."
            value={input}
            onChange={(e) => setInput(e.target.value)}
            disabled={isLoading}
            className="flex-1 px-5 py-3.5 rounded-2xl bg-white border border-gray-200 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 text-sm font-medium"
          />
          <button
            type="submit"
            disabled={!input.trim() || isLoading}
            className="w-12 h-12 rounded-2xl bg-emerald-600 hover:bg-emerald-700 disabled:bg-gray-200 text-white flex items-center justify-center shadow-md transition-all shrink-0"
          >
            {isLoading ? <Loader2 size={18} className="animate-spin" /> : <Send size={18} strokeWidth={2.5} />}
          </button>
        </form>
      </div>
    </div>
  );
};

export default AIChatScreen;
