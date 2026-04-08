import React, { useState, useRef, useEffect } from 'react';
import { Camera, Plus, History, TrendingUp, Search, Sparkles, Flame, Apple, Zap, Droplets, ChevronRight, X, Loader2, User } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { useNavigate } from 'react-router-dom';
import { analyzeFoodImage } from '../services/geminiService';
import { saveScanResult, updateWaterIntake } from '../services/storageService';
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
  const [showSearch, setShowSearch] = useState(false);
  const [showManualLog, setShowManualLog] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [manualMeal, setManualMeal] = useState({
    foodName: '',
    calories: 0,
    protein: 0,
    carbs: 0,
    fats: 0
  });
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
            details: result.details,
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

  const handleAddWater = async (amount: number) => {
    triggerHaptic(hapticPatterns.light);
    await updateWaterIntake(amount);
  };

  const handleSearch = (query: string) => {
    setSearchQuery(query);
    if (!query.trim()) {
      setSearchResults([]);
      return;
    }
    const results = Object.entries(FOOD_DATABASE)
      .filter(([key]) => key.includes(query.toLowerCase()))
      .map(([_, data]) => data);
    setSearchResults(results);
  };

  const logFood = async (food: Partial<ScanResult>) => {
    setIsProcessing(true);
    try {
      const scanData: Omit<ScanResult, 'id' | 'userId' | 'timestamp'> = {
        foodName: food.foodName || 'Unknown',
        type: 'food',
        calories: food.calories || 0,
        protein: food.protein || 0,
        carbs: food.carbs || 0,
        fats: food.fats || 0,
        imageUrl: 'https://picsum.photos/seed/food/200/200', // Placeholder for manual logs
        confidence: 1
      };
      const savedScan = await saveScanResult(scanData);
      triggerHaptic(hapticPatterns.success);
      setShowSearch(false);
      setShowManualLog(false);
      navigate(`/result/${savedScan.id}`);
    } catch (error) {
      console.error("Manual log failed", error);
      triggerHaptic(hapticPatterns.error);
    } finally {
      setIsProcessing(false);
    }
  };

  const handleManualSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!manualMeal.foodName) return;
    await logFood(manualMeal);
  };

  const calorieProgress = (profile?.calorieLimit && profile.calorieLimit > 0) 
    ? (dailySummary?.totalCalories || 0) / profile.calorieLimit 
    : 0;
  const waterProgress = (profile?.waterGoal && profile.waterGoal > 0) 
    ? (dailySummary?.totalWater || 0) / profile.waterGoal 
    : (dailySummary?.totalWater || 0) / 2500;

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
        <div className="flex items-center gap-3">
          <button 
            onClick={() => setShowSearch(true)}
            className="w-12 h-12 rounded-full bg-white border border-gray-100 flex items-center justify-center shadow-sm ios-tap text-gray-400 hover:text-green-600 transition-colors"
          >
            <Search size={20} />
          </button>
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

      {/* Water Tracker Section */}
      <motion.div 
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="glass-card p-8 rounded-[40px] ios-shadow space-y-6 relative overflow-hidden"
      >
        <div className="absolute -top-10 -right-10 opacity-[0.03] pointer-events-none">
          <Droplets size={200} className="text-blue-600" />
        </div>
        
        <div className="flex items-center justify-between relative z-10">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-blue-500/10 rounded-2xl flex items-center justify-center text-blue-500">
              <Droplets size={20} strokeWidth={2.5} />
            </div>
            <div>
              <h3 className="font-bold text-gray-900 tracking-tight">Hydration</h3>
              <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">Daily Water Intake</p>
            </div>
          </div>
          <div className="text-right">
            <span className="text-2xl font-black text-gray-900 tracking-tight">
              {dailySummary?.totalWater || 0}
            </span>
            <span className="text-xs font-bold text-gray-400 ml-1">/ {profile?.waterGoal || 2500}ml</span>
          </div>
        </div>

        <div className="h-32 bg-gray-100/50 rounded-[40px] overflow-hidden border border-white/20 relative z-10 group shadow-inner">
          {/* Liquid Fill */}
          <motion.div 
            initial={{ height: 0 }}
            animate={{ height: `${Math.min(waterProgress * 100, 100)}%` }}
            transition={{ type: 'spring', damping: 25, stiffness: 40 }}
            className="absolute bottom-0 left-0 right-0 bg-gradient-to-b from-blue-400 to-blue-600"
          >
            {/* Primary Wave */}
            <motion.div 
              animate={{ 
                x: [-100, 0],
              }}
              transition={{ 
                duration: 3, 
                repeat: Infinity, 
                ease: "linear" 
              }}
              className="absolute -top-6 left-0 w-[200%] h-12 opacity-50"
            >
              <svg viewBox="0 0 1000 100" preserveAspectRatio="none" className="w-full h-full fill-blue-400">
                <path d="M0,50 C150,100 350,0 500,50 C650,100 850,0 1000,50 L1000,100 L0,100 Z" />
              </svg>
            </motion.div>

            {/* Secondary Wave */}
            <motion.div 
              animate={{ 
                x: [0, -100],
              }}
              transition={{ 
                duration: 5, 
                repeat: Infinity, 
                ease: "linear" 
              }}
              className="absolute -top-4 left-0 w-[200%] h-10 opacity-30"
            >
              <svg viewBox="0 0 1000 100" preserveAspectRatio="none" className="w-full h-full fill-blue-300">
                <path d="M0,50 C150,0 350,100 500,50 C650,0 850,100 1000,50 L1000,100 L0,100 Z" />
              </svg>
            </motion.div>

            {/* Bubbles */}
            {[...Array(5)].map((_, i) => (
              <motion.div
                key={i}
                animate={{
                  y: [-20, -120],
                  opacity: [0, 1, 0],
                  x: [0, (i - 2) * 10]
                }}
                transition={{
                  duration: 2 + Math.random() * 2,
                  repeat: Infinity,
                  delay: Math.random() * 2
                }}
                className="absolute bottom-0 w-1 h-1 bg-white/40 rounded-full"
                style={{ left: `${20 + i * 15}%` }}
              />
            ))}
          </motion.div>

          {/* Percentage Display Overlay */}
          <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
            <span className={cn(
              "text-4xl font-black transition-colors duration-500 tracking-tighter",
              waterProgress > 0.4 ? "text-white" : "text-blue-600"
            )}>
              {Math.round(waterProgress * 100)}%
            </span>
            <span className={cn(
              "text-[10px] font-bold uppercase tracking-widest transition-colors duration-500",
              waterProgress > 0.4 ? "text-white/60" : "text-blue-400"
            )}>
              Daily Goal
            </span>
          </div>
        </div>

        <div className="flex gap-3 relative z-10">
          {[250, 500].map((amount) => (
            <button
              key={amount}
              onClick={() => handleAddWater(amount)}
              className="flex-1 py-3 glass rounded-2xl text-xs font-bold text-blue-600 hover:bg-blue-50 transition-all ios-tap flex items-center justify-center gap-2"
            >
              <Plus size={14} strokeWidth={3} />
              {amount}ml
            </button>
          ))}
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
            <p className="text-white/60 text-[8px] font-black uppercase tracking-widest mt-1">Powered by Gemini 3.1 Pro</p>
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
          onClick={() => setShowManualLog(true)}
          className="glass p-6 rounded-[32px] text-gray-900 space-y-4 shadow-sm border border-white/50 hover:border-green-200 transition-all group ios-shadow"
        >
          <div className="w-12 h-12 bg-blue-50/50 rounded-2xl flex items-center justify-center text-blue-600 group-hover:scale-110 transition-transform ios-shadow">
            <Plus size={24} strokeWidth={2.5} />
          </div>
          <div className="text-left">
            <p className="font-bold text-lg tracking-tight">Manual Log</p>
            <p className="text-gray-400 text-[10px] font-bold uppercase tracking-widest">Input Details</p>
          </div>
        </button>
      </div>

      {/* AI Coach Button */}
      <button 
        onClick={() => navigate('/chat')}
        className="w-full glass p-6 rounded-[32px] flex items-center justify-between shadow-sm border border-white/50 hover:border-green-200 transition-all group ios-shadow"
      >
        <div className="flex items-center gap-4">
          <div className="w-12 h-12 bg-green-50/50 rounded-2xl flex items-center justify-center text-green-600 group-hover:scale-110 transition-transform ios-shadow">
            <Sparkles size={24} strokeWidth={2.5} />
          </div>
          <div className="text-left">
            <p className="font-bold text-lg tracking-tight">AI Health Coach</p>
            <p className="text-gray-400 text-[10px] font-bold uppercase tracking-widest">Personalized Advice & Insights</p>
          </div>
        </div>
        <ChevronRight className="text-gray-300 group-hover:text-green-500 transition-colors" />
      </button>

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

      {/* Search Modal */}
      <AnimatePresence>
        {showSearch && (
          <div className="fixed inset-0 z-[110] flex items-start justify-center p-6 pt-20">
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setShowSearch(false)}
              className="absolute inset-0 bg-black/40 backdrop-blur-sm"
            />
            <motion.div 
              initial={{ opacity: 0, scale: 0.95, y: -20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: -20 }}
              className="glass-card w-full max-w-lg p-6 rounded-[40px] ios-shadow relative z-10 space-y-6"
            >
              <div className="flex items-center gap-3 bg-gray-100/50 p-4 rounded-2xl border border-white/20">
                <Search size={20} className="text-gray-400" />
                <input 
                  autoFocus
                  type="text"
                  placeholder="Search for food (e.g. pizza, apple)..."
                  value={searchQuery}
                  onChange={(e) => handleSearch(e.target.value)}
                  className="bg-transparent border-none focus:outline-none w-full font-bold text-gray-900"
                />
                <button onClick={() => setShowSearch(false)}>
                  <X size={20} className="text-gray-400" />
                </button>
              </div>

              <div className="max-h-[400px] overflow-y-auto space-y-2 scrollbar-hide">
                {searchResults.map((result, idx) => (
                  <button
                    key={idx}
                    onClick={() => logFood(result)}
                    className="w-full flex items-center justify-between p-4 glass hover:bg-green-50 rounded-2xl border border-white/50 transition-all ios-tap group"
                  >
                    <div className="text-left">
                      <p className="font-bold text-gray-900">{result.foodName}</p>
                      <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">
                        {result.calories} kcal • P: {result.protein}g • C: {result.carbs}g • F: {result.fats}g
                      </p>
                    </div>
                    <Plus size={20} className="text-gray-300 group-hover:text-green-500 transition-colors" />
                  </button>
                ))}
                {searchQuery && searchResults.length === 0 && (
                  <div className="text-center py-10 space-y-4">
                    <div className="w-16 h-16 bg-gray-50 rounded-full flex items-center justify-center mx-auto text-gray-300">
                      <Apple size={32} />
                    </div>
                    <p className="text-gray-400 font-bold text-sm">No results found for "{searchQuery}"</p>
                    <button 
                      onClick={() => {
                        setShowSearch(false);
                        setShowManualLog(true);
                        setManualMeal(prev => ({ ...prev, foodName: searchQuery }));
                      }}
                      className="text-green-600 font-bold text-xs bg-green-50 px-4 py-2 rounded-full border border-green-100"
                    >
                      Log Manually Instead
                    </button>
                  </div>
                )}
                {!searchQuery && (
                  <div className="text-center py-10">
                    <p className="text-gray-400 font-bold text-sm">Try searching for common foods</p>
                  </div>
                )}
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

      {/* Manual Log Modal */}
      <AnimatePresence>
        {showManualLog && (
          <div className="fixed inset-0 z-[110] flex items-center justify-center p-6">
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setShowManualLog(false)}
              className="absolute inset-0 bg-black/40 backdrop-blur-sm"
            />
            <motion.div 
              initial={{ opacity: 0, scale: 0.9, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.9, y: 20 }}
              className="glass-card w-full max-w-md p-8 rounded-[40px] ios-shadow relative z-10 space-y-6"
            >
              <div className="flex items-center justify-between">
                <h3 className="text-2xl font-black text-gray-900 tracking-tight">Manual Log</h3>
                <button onClick={() => setShowManualLog(false)} className="text-gray-400 hover:text-gray-600">
                  <X size={24} />
                </button>
              </div>

              <form onSubmit={handleManualSubmit} className="space-y-6">
                <div className="space-y-2">
                  <label className="text-[10px] font-black text-gray-400 uppercase tracking-widest">Meal Name</label>
                  <input 
                    required
                    type="text"
                    value={manualMeal.foodName}
                    onChange={(e) => setManualMeal(prev => ({ ...prev, foodName: e.target.value }))}
                    placeholder="e.g. Homemade Pasta"
                    className="w-full p-4 glass rounded-2xl border border-white/50 focus:outline-none focus:border-green-500 font-bold text-gray-900"
                  />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <label className="text-[10px] font-black text-gray-400 uppercase tracking-widest">Calories (kcal)</label>
                    <input 
                      type="number"
                      value={manualMeal.calories || ''}
                      onChange={(e) => setManualMeal(prev => ({ ...prev, calories: parseInt(e.target.value) || 0 }))}
                      className="w-full p-4 glass rounded-2xl border border-white/50 focus:outline-none focus:border-green-500 font-bold text-gray-900"
                    />
                  </div>
                  <div className="space-y-2">
                    <label className="text-[10px] font-black text-gray-400 uppercase tracking-widest">Protein (g)</label>
                    <input 
                      type="number"
                      value={manualMeal.protein || ''}
                      onChange={(e) => setManualMeal(prev => ({ ...prev, protein: parseInt(e.target.value) || 0 }))}
                      className="w-full p-4 glass rounded-2xl border border-white/50 focus:outline-none focus:border-green-500 font-bold text-gray-900"
                    />
                  </div>
                  <div className="space-y-2">
                    <label className="text-[10px] font-black text-gray-400 uppercase tracking-widest">Carbs (g)</label>
                    <input 
                      type="number"
                      value={manualMeal.carbs || ''}
                      onChange={(e) => setManualMeal(prev => ({ ...prev, carbs: parseInt(e.target.value) || 0 }))}
                      className="w-full p-4 glass rounded-2xl border border-white/50 focus:outline-none focus:border-green-500 font-bold text-gray-900"
                    />
                  </div>
                  <div className="space-y-2">
                    <label className="text-[10px] font-black text-gray-400 uppercase tracking-widest">Fats (g)</label>
                    <input 
                      type="number"
                      value={manualMeal.fats || ''}
                      onChange={(e) => setManualMeal(prev => ({ ...prev, fats: parseInt(e.target.value) || 0 }))}
                      className="w-full p-4 glass rounded-2xl border border-white/50 focus:outline-none focus:border-green-500 font-bold text-gray-900"
                    />
                  </div>
                </div>

                <button 
                  type="submit"
                  disabled={isProcessing || !manualMeal.foodName}
                  className="w-full py-5 bg-green-600 text-white rounded-[24px] font-bold shadow-xl shadow-green-600/20 hover:bg-green-700 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                >
                  {isProcessing ? <Loader2 size={20} className="animate-spin" /> : 'Log Meal'}
                </button>
              </form>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

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
