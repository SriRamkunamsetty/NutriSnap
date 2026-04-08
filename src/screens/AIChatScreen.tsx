import React, { useState, useRef, useEffect } from 'react';
import { Send, Sparkles, User, Bot, Loader2, Info, MessageSquare, Camera } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { getAICoachResponse } from '../services/geminiService';
import { saveChatMessage, getChatHistory, uploadAIAvatar } from '../services/storageService';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { useUser } from '../contexts/UserContext';
import ReactMarkdown from 'react-markdown';
import { ChatMessage } from '../types';

const AIChatScreen: React.FC = () => {
  const { profile, scans, dailySummary, refreshProfile } = useUser();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isUploadingAvatar, setIsUploadingAvatar] = useState(false);
  const [suggestions, setSuggestions] = useState<string[]>([]);
  const scrollRef = useRef<HTMLDivElement>(null);
  const aiAvatarInputRef = useRef<HTMLInputElement>(null);

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
  }, [messages, isLoading, suggestions]);

  const handleSend = async (textToSend?: string) => {
    const messageText = textToSend || input.trim();
    if (!messageText || isLoading) return;

    if (!textToSend) setInput('');
    setSuggestions([]);
    setIsLoading(true);
    triggerHaptic(hapticPatterns.medium);

    try {
      await refreshProfile();
      
      // Use the latest context data directly to ensure AI has most recent state
      // Note: context values might still be stale in the current render cycle, 
      // but refreshProfile ensures the underlying data is updated in Firestore.
      // The getAICoachResponse will use the values passed to it.
      
      await saveChatMessage('user', messageText);
      const result = await getAICoachResponse(
        [...messages, { role: 'user', text: messageText } as any].map(m => ({ role: m.role, text: m.text })),
        profile,
        dailySummary,
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

  const handleAIAvatarChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsUploadingAvatar(true);
    triggerHaptic(hapticPatterns.medium);
    
    try {
      await uploadAIAvatar(file);
      await refreshProfile();
      triggerHaptic(hapticPatterns.success);
    } catch (error) {
      console.error("AI Avatar upload failed", error);
      triggerHaptic(hapticPatterns.error);
    } finally {
      setIsUploadingAvatar(false);
    }
  };

  return (
    <div className="flex flex-col h-[calc(100vh-110px)] bg-transparent">
      {/* Messages Area */}
      <div 
        ref={scrollRef}
        className="flex-1 overflow-y-auto p-6 space-y-6 no-scrollbar"
      >
        <div className="flex justify-center mb-4">
          <div className="glass px-4 py-1.5 rounded-full flex items-center gap-2 border border-white/50 shadow-sm">
            <Sparkles size={12} className="text-green-500" />
            <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">Powered by Gemini 3.1 Pro</span>
          </div>
        </div>
        {messages.map((msg) => (
          <motion.div 
            key={msg.id}
            initial={{ opacity: 0, y: 10, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            className={`flex items-end gap-3 ${msg.role === 'user' ? 'flex-row-reverse' : 'flex-row'}`}
          >
            {/* Avatar */}
            <div className="flex-shrink-0 mb-6 relative group">
              {msg.role === 'user' ? (
                <div className="w-8 h-8 bg-green-500 rounded-xl flex items-center justify-center text-white text-xs font-bold shadow-sm overflow-hidden">
                  {profile?.photoURL ? (
                    <img src={profile.photoURL} alt="User" className="w-full h-full object-cover" referrerPolicy="no-referrer" />
                  ) : (
                    <User size={16} />
                  )}
                </div>
              ) : (
                <button 
                  onClick={() => aiAvatarInputRef.current?.click()}
                  disabled={isUploadingAvatar}
                  className="w-8 h-8 bg-purple-500 rounded-xl flex items-center justify-center text-white text-xs font-bold shadow-sm overflow-hidden relative group"
                >
                  {profile?.aiAvatarURL ? (
                    <img src={profile.aiAvatarURL} alt="AI" className="w-full h-full object-cover" referrerPolicy="no-referrer" />
                  ) : (
                    <Bot size={16} />
                  )}
                  <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity">
                    {isUploadingAvatar ? <Loader2 size={12} className="animate-spin" /> : <Camera size={12} />}
                  </div>
                </button>
              )}
            </div>

            <div className={`flex flex-col max-w-[75%] ${msg.role === 'user' ? 'items-end' : 'items-start'}`}>
              <div className={`px-5 py-3.5 rounded-[24px] text-sm leading-relaxed ios-shadow ${
                msg.role === 'user' 
                  ? 'bg-green-600 text-white rounded-br-none font-medium' 
                  : 'glass-card text-gray-800 rounded-bl-none border-white/50'
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
            className="flex justify-start items-end gap-3"
          >
            <div className="w-8 h-8 bg-purple-500 rounded-xl flex items-center justify-center text-white shadow-sm overflow-hidden">
              {profile?.aiAvatarURL ? (
                <img src={profile.aiAvatarURL} alt="AI" className="w-full h-full object-cover" referrerPolicy="no-referrer" />
              ) : (
                <Bot size={16} />
              )}
            </div>
            <div className="glass-card px-5 py-4 rounded-[24px] rounded-bl-none border-white/50 flex gap-1.5 ios-shadow">
              <div className="w-1.5 h-1.5 bg-green-500 rounded-full animate-bounce" />
              <div className="w-1.5 h-1.5 bg-green-500 rounded-full animate-bounce [animation-delay:0.2s]" />
              <div className="w-1.5 h-1.5 bg-green-500 rounded-full animate-bounce [animation-delay:0.4s]" />
            </div>
          </motion.div>
        )}

        {/* Suggestions */}
        {!isLoading && suggestions.length > 0 && (
          <motion.div 
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="flex flex-wrap gap-2 pt-2"
          >
            {suggestions.map((suggestion, idx) => (
              <button
                key={idx}
                onClick={() => handleSend(suggestion)}
                className="px-4 py-2 glass hover:bg-white/60 rounded-full text-xs font-bold text-green-600 border border-green-100 ios-shadow ios-tap flex items-center gap-2"
              >
                <MessageSquare size={12} />
                {suggestion}
              </button>
            ))}
          </motion.div>
        )}
      </div>

      {/* Input Area */}
      <div className="px-6 pb-4 pt-2">
        <input 
          type="file" 
          ref={aiAvatarInputRef} 
          onChange={handleAIAvatarChange} 
          accept="image/*" 
          className="hidden" 
        />
        <form 
          onSubmit={(e) => { e.preventDefault(); handleSend(); }}
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
