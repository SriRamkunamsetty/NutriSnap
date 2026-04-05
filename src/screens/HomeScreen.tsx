import React, { useState, useRef, useEffect } from 'react';
import { Camera, Plus, History, TrendingUp, Search, Sparkles, Flame, Apple, Zap, Droplets, ChevronRight, X, Loader2, User } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { useNavigate } from 'react-router-dom';
import { analyzeFoodImage } from '../services/geminiService';
import { saveScanResult } from '../services/storageService';
import { ScanResult } from '../types';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { sendLocalNotification } from '../lib/notifications';
import { useUser } from '../contexts/UserContext';

const FOOD_DATABASE: Record<string, Partial<ScanResult>> = {
  'pizza': { foodName: 'Pizza Slice', calories: 285, protein: 12, carbs: 36, fats: 10, type: 'food', confidence: 0.8 },
  'burger': { foodName: 'Classic Burger', calories: 550, protein: 25, carbs: 45, fats: 30, type: 'food', confidence: 0.8 },
  'salad': { foodName: 'Garden Salad', calories: 150, protein: 5, carbs: 10, fats: 8, type: 'food', confidence: 0.8 },
  'apple': { foodName: 'Red Apple', calories: 95, protein: 0.5, carbs: 25, fats: 0.3, type: 'food', confidence: 0.9 },
  'chicken': { foodName: 'Grilled Chicken', calories: 330, protein: 50, carbs: 0, fats: 12, type: 'food', confidence: 0.85 },
};

const HomeScreen: React.FC = () => {
  const navigate = useNavigate();
  const { profile, scans, dailySummary } = useUser();
  const [isProcessing, setIsProcessing] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Notification logic
  useEffect(() => {
    if (profile && dailySummary) {
      const today = new Date().toISOString().split('T')[0];
      const lastNotifiedDate = localStorage.getItem('last_calorie_notification_date');
      
      if (dailySummary.totalCalories > profile.calorieLimit && lastNotifiedDate !== today) {
        sendLocalNotification(
          "Calorie Limit Exceeded!",
          { body: `You've consumed ${dailySummary.totalCalories} kcal today, which is over your limit of ${profile.calorieLimit} kcal.` }
        );
        localStorage.setItem('last_calorie_notification_date', today);
      }
    }
  }, [dailySummary, profile]);

  const handleImageCapture = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsProcessing(true);
    triggerHaptic(hapticPatterns.medium);

    try {
      const reader = new FileReader();
      reader.onloadend = async () => {
        const base64 = (reader.result as string).split(',')[1];
        let result: Partial<ScanResult>;
        
        try {
          result = await analyzeFoodImage(base64, file.type);
        } catch (apiError) {
          console.warn("AI Analysis failed, using fallback mechanism", apiError);
          // Fallback: Try to find a match in local database based on filename or use default
          const fileName = file.name.toLowerCase();
          const match = Object.keys(FOOD_DATABASE).find(key => fileName.includes(key));
          result = match ? FOOD_DATABASE[match] : {
            foodName: 'Unknown Meal',
            type: 'food',
            calories: 450, // Default estimation
            protein: 15,
            carbs: 40,
            fats: 20,
            confidence: 0.5,
            description: "We couldn't reach the AI, so we've provided a standard estimation for a balanced meal."
          };
        }
        
        if (result.foodName) {
          const scanData: Omit<ScanResult, 'id' | 'userId' | 'timestamp'> = {
            foodName: result.foodName,
            type: result.type as any || 'food',
            description: result.description,
            calories: result.calories || 0,
            protein: result.protein || 0,
            carbs: result.carbs || 0,
            fats: result.fats || 0,
            imageUrl: reader.result as string,
            confidence: result.confidence || 0
          };

          const savedScan = await saveScanResult(scanData);
          triggerHaptic(hapticPatterns.success);
          navigate(`/result/${savedScan.id}`);
        }
      };
      reader.readAsDataURL(file);
    } catch (error) {
      console.error("Scan process failed", error);
      triggerHaptic(hapticPatterns.error);
      alert("Failed to process image. Please try again.");
    } finally {
      setIsProcessing(false);
    }
  };

  const calorieProgress = profile ? (dailySummary?.totalCalories || 0) / profile.calorieLimit : 0;

  return (
    <div className="space-y-10 pb-10 pt-8">
      {/* Header */}
      <div className="flex items-center justify-between px-1">
        <div className="space-y-1">
          <h1 className="text-3xl font-bold text-gray-900 tracking-tight">
            Hi, <span className="text-green-600">{profile?.displayName?.split(' ')[0] || 'User'}</span>
          </h1>
          <p className="text-sm text-gray-400 font-medium tracking-tight">Your health journey continues.</p>
        </div>
        <div className="w-12 h-12 rounded-full bg-white border border-gray-100 flex items-center justify-center shadow-sm overflow-hidden relative ios-tap">
          {profile?.photoURL ? (
            <img 
              src={profile.photoURL} 
              alt="Profile" 
              className="w-full h-full object-cover"
              referrerPolicy="no-referrer"
            />
          ) : (
            <User size={20} className="text-gray-400" />
          )}
          <div className="absolute bottom-0 right-0 w-3 h-3 bg-green-500 rounded-full border-2 border-white animate-pulse" />
        </div>
      </div>

      {/* Daily Progress Card - Glassmorphic */}
      <motion.div 
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="glass-card p-8 rounded-[40px] relative overflow-hidden ios-shadow"
      >
        <div className="absolute -top-10 -right-10 opacity-[0.03] pointer-events-none">
          <Flame size={240} className="text-green-600" />
        </div>
        
        <div className="relative z-10 space-y-8">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse" />
              <h2 className="text-sm font-bold text-gray-400 uppercase tracking-widest">Daily Fuel</h2>
            </div>
            <span className="text-xs font-black text-green-600 bg-green-50/50 px-3 py-1 rounded-full border border-green-100">
              {Math.round(calorieProgress * 100)}%
            </span>
          </div>

          <div className="flex items-baseline gap-2">
            <span className="text-6xl font-black text-gray-900 tracking-tighter">
              {dailySummary?.totalCalories || 0}
            </span>
            <span className="text-gray-400 font-bold text-sm tracking-tight">
              / {profile?.calorieLimit || 2000} kcal
            </span>
          </div>

          <div className="h-3 bg-gray-100/50 rounded-full overflow-hidden border border-white/20">
            <motion.div 
              initial={{ width: 0 }}
              animate={{ width: `${Math.min(calorieProgress * 100, 100)}%` }}
              className={cn(
                "h-full rounded-full transition-all duration-1000",
                calorieProgress > 1 ? "bg-red-500" : "bg-green-500"
              )}
            />
          </div>

          <div className="grid grid-cols-3 gap-6 pt-2">
            {[
              { label: 'Protein', value: dailySummary?.totalProtein || 0, color: 'bg-blue-500' },
              { label: 'Carbs', value: dailySummary?.totalCarbs || 0, color: 'bg-orange-500' },
              { label: 'Fats', value: dailySummary?.totalFats || 0, color: 'bg-purple-500' }
            ].map((macro) => (
              <div key={macro.label} className="space-y-2">
                <div className="flex items-center gap-1.5">
                  <div className={cn("w-1.5 h-1.5 rounded-full", macro.color)} />
                  <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{macro.label}</p>
                </div>
                <p className="text-lg font-bold text-gray-900">{macro.value}<span className="text-[10px] text-gray-400 ml-0.5">g</span></p>
              </div>
            ))}
          </div>
        </div>
      </motion.div>

      {/* Quick Actions */}
      <div className="grid grid-cols-2 gap-5">
        <button 
          onClick={() => fileInputRef.current?.click()}
          className="bg-green-600 p-6 rounded-[32px] text-white space-y-4 shadow-xl shadow-green-600/20 hover:bg-green-700 transition-all group relative overflow-hidden"
        >
          <div className="absolute top-0 right-0 w-24 h-24 bg-white/10 rounded-full -mr-10 -mt-10 blur-2xl" />
          <div className="w-12 h-12 bg-white/20 rounded-2xl flex items-center justify-center group-hover:scale-110 transition-transform ios-shadow">
            <Camera size={24} strokeWidth={2.5} />
          </div>
          <div className="text-left">
            <p className="font-bold text-lg tracking-tight">Scan Meal</p>
            <p className="text-white/60 text-[10px] font-bold uppercase tracking-widest">AI Vision</p>
          </div>
        </button>
        <input 
          type="file" 
          ref={fileInputRef} 
          onChange={handleImageCapture} 
          accept="image/*" 
          className="hidden" 
        />

        <button 
          onClick={() => navigate('/chat')}
          className="glass p-6 rounded-[32px] text-gray-900 space-y-4 shadow-sm border border-white/50 hover:border-green-200 transition-all group ios-shadow"
        >
          <div className="w-12 h-12 bg-green-50/50 rounded-2xl flex items-center justify-center text-green-600 group-hover:scale-110 transition-transform ios-shadow">
            <Sparkles size={24} strokeWidth={2.5} />
          </div>
          <div className="text-left">
            <p className="font-bold text-lg tracking-tight">AI Coach</p>
            <p className="text-gray-400 text-[10px] font-bold uppercase tracking-widest">Get Advice</p>
          </div>
        </button>
      </div>

      {/* Last Scan Preview - Dynamic */}
      {scans.length > 0 && (
        <div className="space-y-4">
          <div className="flex items-center justify-between px-1">
            <h3 className="text-sm font-bold text-gray-400 uppercase tracking-widest">Last Scan</h3>
            <button 
              onClick={() => navigate('/history')}
              className="text-green-600 text-xs font-bold flex items-center gap-1 hover:opacity-70"
            >
              History <ChevronRight size={14} />
            </button>
          </div>

          <motion.div 
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            onClick={() => navigate(`/result/${scans[0].id}`)}
            className="glass-card p-5 rounded-[32px] flex items-center gap-5 hover:border-green-200 transition-all cursor-pointer ios-shadow group"
          >
            <div className="w-20 h-20 rounded-2xl overflow-hidden bg-gray-100 flex-shrink-0 ios-shadow group-hover:scale-105 transition-transform">
              <img src={scans[0].imageUrl} alt={scans[0].foodName} className="w-full h-full object-cover" referrerPolicy="no-referrer" />
            </div>
            <div className="flex-1 min-w-0 space-y-1">
              <h4 className="font-bold text-gray-900 truncate text-lg tracking-tight">{scans[0].foodName}</h4>
              <div className="flex items-center gap-2">
                {scans[0].type === 'food' ? (
                  <span className="text-[10px] font-bold text-green-600 bg-green-50/50 px-2 py-0.5 rounded-full border border-green-100">
                    {scans[0].calories} kcal
                  </span>
                ) : (
                  <span className="text-[10px] font-bold text-blue-600 bg-blue-50/50 px-2 py-0.5 rounded-full border border-blue-100 uppercase tracking-widest">
                    {scans[0].type}
                  </span>
                )}
                <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">
                  {new Date(scans[0].timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                </span>
              </div>
            </div>
            <div className="w-10 h-10 rounded-full bg-gray-50 flex items-center justify-center text-gray-300 group-hover:text-green-500 group-hover:bg-green-50 transition-all">
              <ChevronRight size={20} />
            </div>
          </motion.div>
        </div>
      )}

      {/* Processing Overlay */}
      <AnimatePresence>
        {isProcessing && (
          <motion.div 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-white/80 backdrop-blur-xl z-[100] flex flex-col items-center justify-center p-8 text-center"
          >
            <div className="w-24 h-24 glass rounded-[40px] flex items-center justify-center mb-8 ios-shadow">
              <Loader2 className="text-green-600 animate-spin" size={48} strokeWidth={2.5} />
            </div>
            <h2 className="text-3xl font-bold text-gray-900 mb-3 tracking-tight">AI is Analyzing</h2>
            <p className="text-gray-500 max-w-xs font-medium leading-relaxed">Identifying ingredients and calculating nutrition for your meal.</p>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

function cn(...inputs: any[]) {
  return inputs.filter(Boolean).join(' ');
}

export default HomeScreen;
