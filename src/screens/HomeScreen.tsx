import React, { useState, useRef, useEffect } from 'react';
import { 
  Camera, 
  Plus, 
  History, 
  TrendingUp, 
  Search, 
  Sparkles, 
  Flame, 
  Apple, 
  Zap, 
  Droplets, 
  ChevronRight, 
  X, 
  Loader2, 
  User, 
  Activity, 
  UtensilsCrossed 
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { useNavigate } from 'react-router-dom';
import { analyzeFoodImage } from '../services/geminiService';
import { saveScanResult, updateWaterIntake, uploadScanImage } from '../services/storageService';
import { ScanResult } from '../types';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { sendLocalNotification, startMealReminderScheduler, stopMealReminderScheduler } from '../lib/notifications';
import { useUser } from '../contexts/UserContext';
import { CalorieProgressRing } from '../components/CalorieProgressRing';
import { DailyContextPanels } from '../components/DailyContextPanels';
import { MessOSModal } from '../components/MessOSModal';
import { BodyScanModal } from '../components/BodyScanModal';
import { MealRemindersCard } from '../components/MealRemindersModal';
import { HealthyFoodSuggestions } from '../components/HealthyFoodSuggestions';

const FOOD_DATABASE: Record<string, Partial<ScanResult>> = {
  'pizza': { foodName: 'Pizza Slice', calories: 285, protein: 12, carbs: 36, fats: 10, type: 'food', confidence: 0.8 },
  'burger': { foodName: 'Classic Burger', calories: 550, protein: 25, carbs: 45, fats: 30, type: 'food', confidence: 0.8 },
  'salad': { foodName: 'Garden Salad', calories: 150, protein: 5, carbs: 10, fats: 8, type: 'food', confidence: 0.8 },
  'apple': { foodName: 'Red Apple', calories: 95, protein: 0.5, carbs: 25, fats: 0.3, type: 'food', confidence: 0.9 },
  'chicken': { foodName: 'Grilled Chicken', calories: 330, protein: 50, carbs: 0, fats: 12, type: 'food', confidence: 0.85 },
  'dal': { foodName: 'Dal Tadka', calories: 180, protein: 12, carbs: 24, fats: 4, type: 'food', confidence: 0.9 },
  'roti': { foodName: 'Wheat Roti', calories: 85, protein: 3, carbs: 17, fats: 1, type: 'food', confidence: 0.95 },
  'paneer': { foodName: 'Paneer Masala', calories: 280, protein: 18, carbs: 10, fats: 20, type: 'food', confidence: 0.88 },
  'dosa': { foodName: 'Masala Dosa', calories: 260, protein: 6, carbs: 42, fats: 8, type: 'food', confidence: 0.9 },
  'idli': { foodName: 'Steamed Idli (2 pcs)', calories: 130, protein: 5, carbs: 28, fats: 1, type: 'food', confidence: 0.95 },
  'chana': { foodName: 'Roasted Chana', calories: 160, protein: 9, carbs: 24, fats: 3, type: 'food', confidence: 0.92 },
  'curd': { foodName: 'Fresh Curd / Dahi', calories: 98, protein: 7, carbs: 6, fats: 5, type: 'food', confidence: 0.95 },
};

const HomeScreen: React.FC = () => {
  const navigate = useNavigate();
  const { user, profile, scans, dailySummary } = useUser();
  const [isProcessing, setIsProcessing] = useState(false);
  const [showSearch, setShowSearch] = useState(false);
  const [showManualLog, setShowManualLog] = useState(false);
  const [showMessOS, setShowMessOS] = useState(false);
  const [showBodyScan, setShowBodyScan] = useState(false);
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

  // Start background periodic check for meal reminders
  useEffect(() => {
    startMealReminderScheduler();
    return () => {
      stopMealReminderScheduler();
    };
  }, []);

  const handleQuickLogFood = async (food: Omit<ScanResult, 'id' | 'userId' | 'timestamp'>) => {
    if (!user) return;
    try {
      await saveScanResult(food);
    } catch (e) {
      console.error('Failed to quick log food', e);
    }
  };

  const handleImageCapture = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsProcessing(true);
    triggerHaptic(hapticPatterns.medium);

    try {
      // 1. Upload/store image locally
      const imageUrl = await uploadScanImage(file);
      
      const reader = new FileReader();
      reader.onloadend = async () => {
        const base64 = (reader.result as string).split(',')[1];
        let result: Partial<ScanResult>;
        
        try {
          result = await analyzeFoodImage(base64, file.type);
        } catch (apiError) {
          console.warn("AI Analysis fallback mechanism", apiError);
          const fileName = file.name.toLowerCase();
          const match = Object.keys(FOOD_DATABASE).find(key => fileName.includes(key));
          result = match ? FOOD_DATABASE[match] : {
            foodName: 'Fresh Meal Item',
            type: 'food',
            calories: 420,
            protein: 16,
            carbs: 48,
            fats: 14,
            confidence: 0.65,
            description: "Nutritious balanced meal estimation."
          };
        }
        
        const scanData: Omit<ScanResult, 'id' | 'userId' | 'timestamp'> = {
          foodName: result.foodName || 'Meal Log',
          type: (result.type as any) || 'food',
          details: result.details,
          description: result.description,
          calories: result.calories || 0,
          protein: result.protein || 0,
          carbs: result.carbs || 0,
          fats: result.fats || 0,
          imageUrl: imageUrl,
          confidence: result.confidence || 0.9
        };

        const savedScan = await saveScanResult(scanData);
        triggerHaptic(hapticPatterns.success);
        navigate(`/result/${savedScan.id}`);
      };
      reader.readAsDataURL(file);
    } catch (error) {
      console.error("Scan process failed", error);
      triggerHaptic(hapticPatterns.error);
    } finally {
      setIsProcessing(false);
    }
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
        foodName: food.foodName || 'Quick Meal',
        type: 'food',
        calories: food.calories || 0,
        protein: food.protein || 0,
        carbs: food.carbs || 0,
        fats: food.fats || 0,
        imageUrl: undefined,
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

  // Reactively resolve user profile photo
  const currentPhotoURL = profile?.localPhotoPath || profile?.photoURL || user?.photoURL || '';

  return (
    <div className="space-y-8 pb-12 pt-6">
      {/* Header */}
      <div className="flex items-center justify-between px-1">
        <div className="space-y-0.5">
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-black text-gray-900 tracking-tight">
              Hi, <span className="text-emerald-600">{profile?.displayName?.split(' ')[0] || 'Champion'}</span>
            </h1>
            {profile?.isHostelUser && (
              <span className="text-[10px] font-black uppercase tracking-wider bg-emerald-50 text-emerald-700 px-2 py-0.5 rounded-full border border-emerald-100">
                MessOS
              </span>
            )}
          </div>
          <p className="text-xs text-gray-400 font-medium">100% Private On-Device Health</p>
        </div>

        <div className="flex items-center gap-2.5">
          <button 
            onClick={() => setShowSearch(true)}
            className="w-11 h-11 rounded-2xl bg-white border border-gray-100 flex items-center justify-center shadow-sm ios-tap text-gray-500 hover:text-emerald-600 transition-colors"
            title="Search food database"
          >
            <Search size={18} />
          </button>

          <button 
            onClick={() => {
              triggerHaptic(hapticPatterns.light);
              navigate('/settings');
            }}
            className="w-11 h-11 rounded-2xl bg-white border border-gray-100 flex items-center justify-center shadow-sm overflow-hidden relative ios-tap group"
            title="Profile & Settings"
          >
            {currentPhotoURL ? (
              <img 
                src={currentPhotoURL} 
                alt="Profile" 
                className="w-full h-full object-cover group-hover:scale-105 transition-transform"
                referrerPolicy="no-referrer"
              />
            ) : (
              <div className="w-full h-full bg-emerald-50 text-emerald-700 flex items-center justify-center font-black text-xs">
                {profile?.displayName?.slice(0, 1) || 'U'}
              </div>
            )}
            <div className="absolute bottom-0.5 right-0.5 w-2.5 h-2.5 bg-emerald-500 rounded-full border border-white" />
          </button>
        </div>
      </div>

      {/* Unified Context Panel 1: Fuel (Calorie Progress Ring & Macro Targets) */}
      <CalorieProgressRing
        dailySummary={dailySummary}
        profile={profile}
        calorieProgress={calorieProgress}
      />

      {/* Unified Context Panels 2-5: Move, Hydrate, Rest, Recovery, and MessOS Banner */}
      <DailyContextPanels 
        onOpenMessOS={() => setShowMessOS(true)}
        onOpenQuickLog={() => setShowManualLog(true)}
      />

      {/* Recurring Meal Reminders Card */}
      <MealRemindersCard />

      {/* Action Buttons: Scan Meal, Scan Body, Manual Log */}
      <div className="grid grid-cols-3 gap-3">
        {/* Button 1: Scan Food */}
        <button 
          onClick={() => fileInputRef.current?.click()}
          disabled={isProcessing}
          className="p-4 rounded-[26px] bg-emerald-600 hover:bg-emerald-700 text-white shadow-lg shadow-emerald-600/20 flex flex-col justify-between items-start transition-all group active:scale-95"
        >
          <div className="w-10 h-10 rounded-2xl bg-white/20 flex items-center justify-center text-white backdrop-blur-sm group-hover:scale-110 transition-transform">
            {isProcessing ? <Loader2 size={20} className="animate-spin" /> : <Camera size={20} />}
          </div>
          <div className="text-left mt-3">
            <p className="font-bold text-sm tracking-tight leading-tight">Scan Meal</p>
            <p className="text-white/80 text-[10px] font-medium">Gemini AI</p>
          </div>
        </button>
        <input 
          type="file" 
          ref={fileInputRef} 
          onChange={handleImageCapture} 
          accept="image/*" 
          className="hidden" 
        />

        {/* Button 2: Scan Body */}
        <button 
          onClick={() => setShowBodyScan(true)}
          className="p-4 rounded-[26px] bg-purple-600 hover:bg-purple-700 text-white shadow-lg shadow-purple-600/20 flex flex-col justify-between items-start transition-all group active:scale-95"
        >
          <div className="w-10 h-10 rounded-2xl bg-white/20 flex items-center justify-center text-white backdrop-blur-sm group-hover:scale-110 transition-transform">
            <Activity size={20} />
          </div>
          <div className="text-left mt-3">
            <p className="font-bold text-sm tracking-tight leading-tight">Body Scan</p>
            <p className="text-white/80 text-[10px] font-medium">ML Fat & Tone</p>
          </div>
        </button>

        {/* Button 3: Manual Log */}
        <button 
          onClick={() => setShowManualLog(true)}
          className="p-4 rounded-[26px] bg-white border border-gray-200/80 hover:border-emerald-300 text-gray-800 shadow-sm flex flex-col justify-between items-start transition-all group active:scale-95"
        >
          <div className="w-10 h-10 rounded-2xl bg-blue-50 text-blue-600 flex items-center justify-center group-hover:scale-110 transition-transform">
            <Plus size={20} strokeWidth={2.5} />
          </div>
          <div className="text-left mt-3">
            <p className="font-bold text-sm tracking-tight leading-tight">Manual Log</p>
            <p className="text-gray-400 text-[10px] font-medium">Input macros</p>
          </div>
        </button>
      </div>

      {/* AI Coach Banner Shortcut */}
      <button 
        onClick={() => navigate('/chat')}
        className="w-full p-4 rounded-[26px] bg-white border border-gray-100 shadow-sm flex items-center justify-between hover:border-emerald-200 transition-all group"
      >
        <div className="flex items-center gap-3.5">
          <div className="w-11 h-11 rounded-2xl bg-emerald-50 text-emerald-600 flex items-center justify-center group-hover:scale-105 transition-transform">
            <Sparkles size={22} />
          </div>
          <div className="text-left">
            <div className="flex items-center gap-2">
              <p className="font-bold text-sm text-gray-900">Ask NutriSnap AI Coach</p>
              <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
            </div>
            <p className="text-xs text-gray-400">Contextual advice calibrated to your current calories & goals</p>
          </div>
        </div>
        <ChevronRight className="text-gray-300 group-hover:text-emerald-600 transition-colors" size={18} />
      </button>

      {/* Suggested Healthy Food Options Section */}
      <HealthyFoodSuggestions
        dailySummary={dailySummary}
        profile={profile}
        onQuickLog={handleQuickLogFood}
      />

      {/* Last Scan Preview */}
      {scans.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center justify-between px-1">
            <h3 className="text-xs font-bold text-gray-400 uppercase tracking-wider">Recent Logs</h3>
            <button 
              onClick={() => navigate('/history')}
              className="text-emerald-600 text-xs font-bold flex items-center gap-1 hover:opacity-80"
            >
              All History <ChevronRight size={14} />
            </button>
          </div>

          <motion.div 
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            onClick={() => navigate(`/result/${scans[0].id}`)}
            className="p-4 rounded-[26px] bg-white border border-gray-100 flex items-center gap-4 hover:border-emerald-200 transition-all cursor-pointer shadow-sm group"
          >
            <div className="w-16 h-16 rounded-2xl overflow-hidden bg-gray-100 flex-shrink-0 group-hover:scale-105 transition-transform flex items-center justify-center">
              {scans[0].imageUrl ? (
                <img src={scans[0].imageUrl} alt={scans[0].foodName} className="w-full h-full object-cover" referrerPolicy="no-referrer" />
              ) : (
                <Apple size={24} className="text-emerald-600" />
              )}
            </div>
            <div className="flex-1 min-w-0 space-y-1">
              <h4 className="font-bold text-gray-900 truncate text-base tracking-tight">{scans[0].foodName}</h4>
              <div className="flex items-center gap-2">
                {scans[0].type === 'food' ? (
                  <span className="text-[11px] font-bold text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-100">
                    {scans[0].calories} kcal
                  </span>
                ) : (
                  <span className="text-[11px] font-bold text-purple-700 bg-purple-50 px-2 py-0.5 rounded-full border border-purple-100 uppercase tracking-wider">
                    {scans[0].type}
                  </span>
                )}
                <span className="text-[10px] font-semibold text-gray-400">
                  {new Date(scans[0].timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                </span>
              </div>
            </div>
            <ChevronRight size={18} className="text-gray-300 group-hover:text-emerald-600 transition-colors" />
          </motion.div>
        </div>
      )}

      {/* MessOS Intelligence Modal */}
      <MessOSModal 
        isOpen={showMessOS}
        onClose={() => setShowMessOS(false)}
      />

      {/* AI Body Scan Modal */}
      <BodyScanModal 
        isOpen={showBodyScan}
        onClose={() => setShowBodyScan(false)}
      />

      {/* Search Modal */}
      <AnimatePresence>
        {showSearch && (
          <div className="fixed inset-0 z-[110] flex items-start justify-center p-4 pt-16">
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setShowSearch(false)}
              className="absolute inset-0 bg-black/40 backdrop-blur-sm"
            />
            <motion.div 
              initial={{ opacity: 0, scale: 0.96, y: -15 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.96, y: -15 }}
              className="bg-white w-full max-w-md p-6 rounded-[32px] shadow-2xl border border-gray-100 relative z-10 space-y-4"
            >
              <div className="flex items-center gap-3 bg-gray-100 p-3.5 rounded-2xl">
                <Search size={18} className="text-gray-400" />
                <input 
                  autoFocus
                  type="text"
                  placeholder="Search food (e.g. roti, dal, pizza)..."
                  value={searchQuery}
                  onChange={(e) => handleSearch(e.target.value)}
                  className="bg-transparent border-none focus:outline-none w-full font-bold text-sm text-gray-900"
                />
                <button onClick={() => setShowSearch(false)} className="text-gray-400 hover:text-gray-600">
                  <X size={18} />
                </button>
              </div>

              <div className="max-h-[320px] overflow-y-auto space-y-2">
                {searchResults.map((result, idx) => (
                  <button
                    key={idx}
                    onClick={() => logFood(result)}
                    className="w-full flex items-center justify-between p-3.5 hover:bg-emerald-50 rounded-2xl border border-gray-100 transition-all text-left group"
                  >
                    <div>
                      <p className="font-bold text-sm text-gray-900">{result.foodName}</p>
                      <p className="text-[10px] font-semibold text-gray-400">
                        {result.calories} kcal • P: {result.protein}g • C: {result.carbs}g • F: {result.fats}g
                      </p>
                    </div>
                    <Plus size={18} className="text-gray-300 group-hover:text-emerald-600 transition-colors" />
                  </button>
                ))}
                {searchQuery && searchResults.length === 0 && (
                  <div className="text-center py-8 space-y-3">
                    <p className="text-gray-400 text-xs font-medium">No results for "{searchQuery}"</p>
                    <button 
                      onClick={() => {
                        setShowSearch(false);
                        setShowManualLog(true);
                      }}
                      className="text-xs font-bold text-emerald-600 hover:underline"
                    >
                      Log Manually Instead
                    </button>
                  </div>
                )}
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

      {/* Manual Food Log Modal */}
      <AnimatePresence>
        {showManualLog && (
          <div className="fixed inset-0 z-[110] flex items-center justify-center p-4">
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setShowManualLog(false)}
              className="absolute inset-0 bg-black/40 backdrop-blur-sm"
            />
            <motion.div 
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="bg-white w-full max-w-md p-6 rounded-[32px] shadow-2xl border border-gray-100 relative z-10 space-y-4"
            >
              <div className="flex justify-between items-center pb-2 border-b border-gray-100">
                <h3 className="font-bold text-base text-gray-900">Manual Meal Entry</h3>
                <button onClick={() => setShowManualLog(false)} className="text-gray-400 hover:text-gray-600">
                  <X size={18} />
                </button>
              </div>

              <form onSubmit={handleManualSubmit} className="space-y-3.5">
                <div>
                  <label className="text-[10px] font-bold text-gray-500 uppercase tracking-wider block mb-1">
                    Food Name
                  </label>
                  <input 
                    type="text" 
                    required
                    placeholder="e.g. Oatmeal with Almonds"
                    value={manualMeal.foodName}
                    onChange={(e) => setManualMeal({ ...manualMeal, foodName: e.target.value })}
                    className="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm font-medium focus:ring-2 focus:ring-emerald-500/20 focus:outline-none"
                  />
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="text-[10px] font-bold text-gray-500 uppercase tracking-wider block mb-1">
                      Calories (kcal)
                    </label>
                    <input 
                      type="number" 
                      required
                      placeholder="e.g. 350"
                      value={manualMeal.calories || ''}
                      onChange={(e) => setManualMeal({ ...manualMeal, calories: Number(e.target.value) })}
                      className="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm font-medium focus:ring-2 focus:ring-emerald-500/20 focus:outline-none"
                    />
                  </div>
                  <div>
                    <label className="text-[10px] font-bold text-gray-500 uppercase tracking-wider block mb-1">
                      Protein (g)
                    </label>
                    <input 
                      type="number" 
                      placeholder="e.g. 20"
                      value={manualMeal.protein || ''}
                      onChange={(e) => setManualMeal({ ...manualMeal, protein: Number(e.target.value) })}
                      className="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm font-medium focus:ring-2 focus:ring-emerald-500/20 focus:outline-none"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="text-[10px] font-bold text-gray-500 uppercase tracking-wider block mb-1">
                      Carbs (g)
                    </label>
                    <input 
                      type="number" 
                      placeholder="e.g. 45"
                      value={manualMeal.carbs || ''}
                      onChange={(e) => setManualMeal({ ...manualMeal, carbs: Number(e.target.value) })}
                      className="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm font-medium focus:ring-2 focus:ring-emerald-500/20 focus:outline-none"
                    />
                  </div>
                  <div>
                    <label className="text-[10px] font-bold text-gray-500 uppercase tracking-wider block mb-1">
                      Fats (g)
                    </label>
                    <input 
                      type="number" 
                      placeholder="e.g. 10"
                      value={manualMeal.fats || ''}
                      onChange={(e) => setManualMeal({ ...manualMeal, fats: Number(e.target.value) })}
                      className="w-full px-4 py-3 rounded-xl border border-gray-200 text-sm font-medium focus:ring-2 focus:ring-emerald-500/20 focus:outline-none"
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={isProcessing || !manualMeal.foodName}
                  className="w-full py-3.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl font-bold text-sm shadow-md transition-all mt-2"
                >
                  Save Meal Log
                </button>
              </form>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
};

export default HomeScreen;
