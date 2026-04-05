import React, { useState, useRef, useEffect } from 'react';
import { Send, Sparkles, User, Bot, Loader2, Info, MessageSquare } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { getAICoachResponse } from '../services/geminiService';
import { saveChatMessage, getChatHistory } from '../services/storageService';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { useUser } from '../contexts/UserContext';
import ReactMarkdown from 'react-markdown';
import { ChatMessage } from '../types';

const AIChatScreen: React.FC = () => {
  const { profile, scans, dailySummary } = useUser();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const unsubscribe = getChatHistory((history) => {
      if (history.length === 0) {
        // Initial greeting
        const greeting: ChatMessage = {
          id: 'greeting',
          userId: profile?.uid || 'system',
          role: 'model',
          text: `Hi ${profile?.displayName?.split(' ')[0] || 'there'}! I'm your NutriSnap AI. How can I help you with your nutrition goals today?`,
          timestamp: new Date().toISOString()
        };
        setMessages([greeting]);
      } else {
        setMessages(history);
      }
    });
    return () => unsubscribe();
  }, [profile]);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  const handleSend = async (e?: React.FormEvent) => {
    e?.preventDefault();
    if (!input.trim() || isLoading) return;

    const userMessage = input.trim();
    setInput('');
    setIsLoading(true);
    triggerHaptic(hapticPatterns.medium);

    try {
      await saveChatMessage('user', userMessage);
      const aiResponse = await getAICoachResponse(
        messages.map(m => ({ role: m.role, text: m.text })),
        profile,
        dailySummary,
        scans
      );
      if (aiResponse) {
        await saveChatMessage('model', aiResponse);
        triggerHaptic(hapticPatterns.success);
      }
    } catch (error) {
      console.error("Chat failed", error);
      triggerHaptic(hapticPatterns.error);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex flex-col h-[calc(100vh-180px)] bg-transparent">
      {/* Chat Header - Integrated into Layout but adding sub-header here */}
      <div className="px-6 py-4 flex items-center justify-between bg-white/40 backdrop-blur-md border-b border-white/20 ios-shadow rounded-t-[32px]">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-green-500 rounded-2xl flex items-center justify-center text-white shadow-lg shadow-green-500/20">
            <Sparkles size={20} strokeWidth={2.5} />
          </div>
          <div>
            <h2 className="font-bold text-gray-900 tracking-tight">AI Nutritionist</h2>
            <div className="flex items-center gap-1.5">
              <div className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse" />
              <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">Active Now</span>
            </div>
          </div>
        </div>
        <button className="w-8 h-8 rounded-full bg-white/50 flex items-center justify-center text-gray-400 hover:text-gray-600 transition-all">
          <Info size={16} />
        </button>
      </div>

      {/* Messages Area */}
      <div 
        ref={scrollRef}
        className="flex-1 overflow-y-auto p-6 space-y-6 no-scrollbar"
      >
        {messages.map((msg) => (
          <motion.div 
            key={msg.id}
            initial={{ opacity: 0, y: 10, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}
          >
            <div className={`flex flex-col max-w-[85%] ${msg.role === 'user' ? 'items-end' : 'items-start'}`}>
              <div className={`px-5 py-3.5 rounded-[24px] text-sm leading-relaxed ios-shadow ${
                msg.role === 'user' 
                  ? 'bg-green-600 text-white rounded-tr-none font-medium' 
                  : 'glass-card text-gray-800 rounded-tl-none border-white/50'
              }`}>
                <div className="prose prose-sm max-w-none">
                  <ReactMarkdown>{msg.text}</ReactMarkdown>
                </div>
              </div>
              <span className="text-[10px] font-bold text-gray-300 uppercase tracking-widest mt-2 px-2">
                {new Date(msg.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </span>
            </div>
          </motion.div>
        ))}
        {isLoading && (
          <motion.div 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="flex justify-start"
          >
            <div className="glass-card px-5 py-4 rounded-[24px] rounded-tl-none border-white/50 flex gap-1.5 ios-shadow">
              <div className="w-1.5 h-1.5 bg-green-500 rounded-full animate-bounce" />
              <div className="w-1.5 h-1.5 bg-green-500 rounded-full animate-bounce [animation-delay:0.2s]" />
              <div className="w-1.5 h-1.5 bg-green-500 rounded-full animate-bounce [animation-delay:0.4s]" />
            </div>
          </motion.div>
        )}
      </div>

      {/* Input Area */}
      <div className="p-6">
        <form 
          onSubmit={handleSend}
          className="relative flex items-center"
        >
          <input 
            type="text" 
            placeholder="Ask NutriSnap AI..." 
            value={input}
            onChange={(e) => setInput(e.target.value)}
            disabled={isLoading}
            className="w-full glass rounded-[28px] py-4 pl-6 pr-14 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-green-500/20 transition-all ios-shadow placeholder:text-gray-400"
          />
          <button 
            type="submit"
            disabled={!input.trim() || isLoading}
            className="absolute right-2 w-11 h-11 bg-green-600 text-white rounded-full flex items-center justify-center shadow-lg hover:bg-green-700 disabled:bg-gray-200 disabled:shadow-none transition-all"
          >
            {isLoading ? <Loader2 size={20} className="animate-spin" /> : <Send size={20} strokeWidth={2.5} />}
          </button>
        </form>
      </div>
    </div>
  );
};

export default AIChatScreen;
