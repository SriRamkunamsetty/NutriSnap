import React from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { ChevronLeft, Share2, Check, Flame, Beef, Wheat, Droplets, Info, User, Dog, Fingerprint, Plus } from 'lucide-react';
import { motion } from 'motion/react';
import { ScanResult } from '../types';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { useUser } from '../contexts/UserContext';
import { saveScanResult } from '../services/storageService';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const ResultScreen: React.FC = () => {
  const { state } = useLocation();
  const navigate = useNavigate();
  const { id } = useParams();
  const { scans, profile, dailySummary } = useUser();
  
  const scan = (state?.scan as ScanResult) || scans.find(s => s.id === id);

  if (!scan) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen p-12 text-center bg-[#F7F8FA]">
        <div className="w-24 h-24 glass text-red-500 rounded-[40px] flex items-center justify-center mb-8 ios-shadow">
          <Info size={48} strokeWidth={1.5} />
        </div>
        <h2 className="text-2xl font-bold text-gray-900 mb-4 tracking-tight">Scan Not Found</h2>
        <p className="text-gray-500 mb-12 max-w-xs mx-auto leading-relaxed font-medium">
          We couldn't find the details for this scan. It might have been deleted or moved.
        </p>
        <button 
          onClick={() => {
            triggerHaptic(hapticPatterns.light);
            navigate('/');
          }}
          className="w-full max-w-xs bg-green-600 text-white py-5 rounded-[24px] font-bold shadow-xl hover:bg-green-700 transition-all ios-shadow"
        >
          Back to Dashboard
        </button>
      </div>
    );
  }

  const getPersonalizedTip = () => {
    if (!profile || !dailySummary || scan.type !== 'food') return null;

    const remainingCalories = profile.calorieLimit - dailySummary.totalCalories;
    const isOverLimit = remainingCalories < 0;
    
    let tip = "";

    if (profile.goal === 'lose') {
      if (scan.calories > 600) {
        tip = "This is a heavy meal for weight loss. Try to keep your next meal under 300 calories.";
      } else if (scan.protein > 20) {
        tip = "Great choice! High protein helps maintain muscle while losing fat.";
      } else {
        tip = "Good portion control. Remember to stay hydrated!";
      }
    } else if (profile.goal === 'gain') {
      if (scan.protein < 15) {
        tip = "You need more protein to build muscle. Consider adding a protein shake.";
      } else if (scan.calories < 400) {
        tip = "This is a light meal. You might need a snack later to reach your surplus goal.";
      } else {
        tip = "Excellent calorie density for your bulking goal!";
      }
    }

    if (isOverLimit) {
      tip += " You've exceeded your daily limit, so focus on light activity like walking tonight.";
    } else if (remainingCalories < 200) {
      tip += " You're almost at your limit for today. Choose your next snack wisely!";
    }

    return tip;
  };

  const personalizedTip = getPersonalizedTip();

  const handleShare = async () => {
    triggerHaptic(hapticPatterns.light);
    
    const shareText = `🍎 NutriSnap Scan: ${scan.foodName}\n\n` +
      (scan.type === 'food' || (scan.calories && scan.calories > 0) ? 
        `🔥 Calories: ${scan.calories} kcal\n` +
        `💪 Protein: ${scan.protein}g\n` +
        `🍞 Carbs: ${scan.carbs}g\n` +
        `💧 Fats: ${scan.fats}g\n\n` : 
        `🤖 AI detected: ${scan.type} (${scan.details})\n\n`) +
      `Track your journey with NutriSnap!`;

    if (navigator.share) {
      try {
        await navigator.share({
          title: `NutriSnap - ${scan.foodName}`,
          text: shareText,
          url: window.location.href,
        });
        triggerHaptic(hapticPatterns.success);
      } catch (error) {
        if (error instanceof Error && error.name !== 'AbortError') {
          console.error('Error sharing:', error);
          triggerHaptic(hapticPatterns.error);
          // Fallback to clipboard if share fails
          try {
            await navigator.clipboard.writeText(`${shareText}\n${window.location.href}`);
            triggerHaptic(hapticPatterns.success);
          } catch (clipError) {
            console.error('Clipboard fallback failed:', clipError);
          }
        }
      }
    } else {
      try {
        await navigator.clipboard.writeText(`${shareText}\n${window.location.href}`);
        triggerHaptic(hapticPatterns.success);
      } catch (err) {
        console.error('Failed to copy:', err);
        triggerHaptic(hapticPatterns.error);
      }
    }
  };

  const handleLogMeal = async () => {
    if (!scan) return;
    triggerHaptic(hapticPatterns.medium);
    
    try {
      const scanData: Omit<ScanResult, 'id' | 'userId' | 'timestamp'> = {
        foodName: scan.foodName,
        type: scan.type,
        details: scan.details,
        description: scan.description,
        calories: scan.calories,
        protein: scan.protein,
        carbs: scan.carbs,
        fats: scan.fats,
        imageUrl: scan.imageUrl,
        confidence: scan.confidence
      };

      await saveScanResult(scanData);
      triggerHaptic(hapticPatterns.success);
      alert("Meal logged successfully!");
    } catch (error) {
      console.error("Failed to log meal", error);
      triggerHaptic(hapticPatterns.error);
    }
  };

  const macros = [
    { label: 'Protein', value: scan.protein, unit: 'g', icon: Beef, color: 'bg-blue-500', textColor: 'text-blue-600', bgColor: 'bg-blue-50/50' },
    { label: 'Carbs', value: scan.carbs, unit: 'g', icon: Wheat, color: 'bg-orange-500', textColor: 'text-orange-600', bgColor: 'bg-orange-50/50' },
    { label: 'Fats', value: scan.fats, unit: 'g', icon: Droplets, color: 'bg-purple-500', textColor: 'text-purple-600', bgColor: 'bg-purple-50/50' },
  ];

  return (
    <div className="flex flex-col min-h-full pb-10">
      {/* Top Image Section */}
      <div className="relative h-[420px] w-[calc(100%+2rem)] -mx-4 -mt-24 mb-6 overflow-hidden rounded-b-[120px] shadow-2xl">
        <img 
          src={scan.imageUrl} 
          alt={scan.foodName} 
          className="w-full h-full object-cover"
          referrerPolicy="no-referrer"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent" />
        
        <button 
          onClick={() => {
            triggerHaptic(hapticPatterns.light);
            navigate('/');
          }}
          className="absolute top-32 left-8 w-12 h-12 bg-white/20 backdrop-blur-xl rounded-full flex items-center justify-center text-white hover:bg-white/40 transition-all border border-white/30 shadow-2xl z-50 active:scale-90"
        >
          <ChevronLeft size={24} strokeWidth={2.5} />
        </button>
        
        <button 
          onClick={handleShare}
          className="absolute top-32 right-8 w-12 h-12 bg-white/20 backdrop-blur-xl rounded-full flex items-center justify-center text-white hover:bg-white/40 transition-all border border-white/30 shadow-2xl z-50 active:scale-90"
        >
          <Share2 size={20} strokeWidth={2.5} />
        </button>

        <div className="absolute bottom-12 left-0 right-0 px-10">
          <motion.div 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="text-center space-y-2"
          >
            <div className="flex items-center justify-center gap-3">
              <span className="bg-green-500 text-white text-[10px] font-black px-4 py-1.5 rounded-full uppercase tracking-[0.2em] shadow-lg">
                AI {(scan.type === 'food' || (scan.calories && scan.calories > 0)) ? 'Verified' : 'Detected'}
              </span>
            </div>
            
            <h1 className="text-4xl font-black text-white tracking-tighter leading-tight drop-shadow-2xl">
              {scan.foodName}
            </h1>
          </motion.div>
        </div>
      </div>

      {/* Quick Stats Bar - Directly below image */}
      {(scan.type === 'food' || (scan.calories && scan.calories > 0)) ? (
        <motion.div 
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          className="glass-card mx-2 mb-10 p-6 rounded-[40px] flex items-center justify-around ios-shadow border-white/50"
        >
          <div className="text-center">
            <p className="text-2xl font-black text-gray-900 tracking-tight">{scan.calories}</p>
            <p className="text-[10px] font-black uppercase tracking-widest text-gray-400">Calories</p>
          </div>
          <div className="w-px h-8 bg-gray-100" />
          <div className="text-center">
            <p className="text-2xl font-black text-blue-600 tracking-tight">{scan.protein}g</p>
            <p className="text-[10px] font-black uppercase tracking-widest text-gray-400">Protein</p>
          </div>
          <div className="w-px h-8 bg-gray-100" />
          <div className="text-center">
            <p className="text-2xl font-black text-orange-600 tracking-tight">{scan.carbs}g</p>
            <p className="text-[10px] font-black uppercase tracking-widest text-gray-400">Carbs</p>
          </div>
          <div className="w-px h-8 bg-gray-100" />
          <div className="text-center">
            <p className="text-2xl font-black text-purple-600 tracking-tight">{scan.fats}g</p>
            <p className="text-[10px] font-black uppercase tracking-widest text-gray-400">Fats</p>
          </div>
        </motion.div>
      ) : (
        <motion.div 
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          className="glass-card mx-2 mb-10 p-6 rounded-[40px] flex items-center justify-around ios-shadow border-white/50"
        >
          <div className="flex flex-col items-center gap-1">
            <div className="w-10 h-10 bg-blue-500/10 rounded-xl flex items-center justify-center text-blue-600">
              {scan.type === 'person' ? <User size={20} /> : scan.type === 'animal' ? <Dog size={20} /> : <Fingerprint size={20} />}
            </div>
            <p className="text-[10px] font-black uppercase tracking-widest text-gray-400 mt-1">Category</p>
            <p className="text-sm font-bold text-gray-900 capitalize">{scan.type}</p>
          </div>
          <div className="w-px h-12 bg-gray-100" />
          <div className="flex flex-col items-center gap-1">
            <div className="w-10 h-10 bg-green-500/10 rounded-xl flex items-center justify-center text-green-600">
              <Check size={20} />
            </div>
            <p className="text-[10px] font-black uppercase tracking-widest text-gray-400 mt-1">
              {scan.type === 'person' ? 'Gender' : scan.type === 'animal' ? 'Species' : 'Details'}
            </p>
            <p className="text-sm font-bold text-gray-900 capitalize">{scan.details || 'Unknown'}</p>
          </div>
          <div className="w-px h-12 bg-gray-100" />
          <div className="flex flex-col items-center gap-1">
            <div className="w-10 h-10 bg-orange-500/10 rounded-xl flex items-center justify-center text-orange-600">
              <Flame size={20} />
            </div>
            <p className="text-[10px] font-black uppercase tracking-widest text-gray-400 mt-1">Confidence</p>
            <p className="text-sm font-bold text-gray-900">{Math.round((scan.confidence || 0) * 100)}%</p>
          </div>
        </motion.div>
      )}

      {/* Content Section */}
      <div className="space-y-8">
        {/* Detailed Macro Cards */}
        {(scan.type === 'food' || (scan.calories && scan.calories > 0)) && (
          <div className="space-y-6">
            <div className="grid grid-cols-3 gap-4">
              {macros.map((macro) => (
                <motion.div 
                  key={macro.label}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="glass-card p-4 rounded-[32px] ios-shadow border-white/50 flex flex-col items-center text-center space-y-2"
                >
                  <div className={cn("w-10 h-10 rounded-2xl flex items-center justify-center shadow-sm", macro.bgColor, macro.textColor)}>
                    <macro.icon size={20} strokeWidth={2.5} />
                  </div>
                  <div>
                    <p className="text-lg font-black text-gray-900 leading-none">{macro.value}<span className="text-[10px] ml-0.5">{macro.unit}</span></p>
                    <p className="text-[10px] font-bold uppercase tracking-widest text-gray-400 mt-1">{macro.label}</p>
                  </div>
                </motion.div>
              ))}
            </div>

            {/* Goal Comparison Section */}
            {profile && (
              <motion.div 
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                className={cn(
                  "glass-card p-6 rounded-[40px] ios-shadow space-y-6 transition-all duration-500",
                  dailySummary && dailySummary.totalCalories > (profile.calorieLimit || 2000) 
                    ? "border-red-200 bg-red-50/30" 
                    : "border-white/50"
                )}
              >
                <div className="flex items-center justify-between px-2">
                  <h4 className="text-sm font-black uppercase tracking-widest text-gray-400">Daily Goal Impact</h4>
                  {dailySummary && dailySummary.totalCalories > (profile.calorieLimit || 2000) && (
                    <div className="flex items-center gap-1.5 text-red-500 animate-pulse">
                      <Flame size={14} strokeWidth={3} />
                      <span className="text-[10px] font-black uppercase tracking-widest">Limit Exceeded</span>
                    </div>
                  )}
                </div>

                {/* Calorie Warning Message */}
                {dailySummary && dailySummary.totalCalories > (profile.calorieLimit || 2000) && (
                  <motion.div 
                    initial={{ scale: 0.9, opacity: 0 }}
                    animate={{ scale: 1, opacity: 1 }}
                    className="mx-2 p-5 bg-white rounded-[32px] border border-red-100 flex items-start gap-4 shadow-sm"
                  >
                    <div className="w-10 h-10 bg-red-500 rounded-2xl flex items-center justify-center text-white shrink-0 shadow-lg shadow-red-500/20">
                      <Flame size={20} strokeWidth={2.5} />
                    </div>
                    <div className="space-y-1">
                      <p className="text-base font-black text-red-900 tracking-tight">
                        {(dailySummary.totalCalories - scan.calories) <= (profile.calorieLimit || 2000) 
                          ? "This meal pushed you over!" 
                          : "Daily Limit Exceeded"}
                      </p>
                      <p className="text-sm text-red-700/80 leading-relaxed font-medium">
                        Your total is now <span className="font-black text-red-900">{dailySummary.totalCalories}</span> kcal. 
                        You are <span className="font-black text-red-900">{dailySummary.totalCalories - (profile.calorieLimit || 2000)}</span> kcal over your daily target.
                      </p>
                    </div>
                  </motion.div>
                )}

                <div className="space-y-6">
                  {[
                    { label: 'Protein', value: scan.protein, total: dailySummary?.totalProtein || 0, goal: profile.proteinGoal || 150, color: 'bg-blue-500' },
                    { label: 'Carbs', value: scan.carbs, total: dailySummary?.totalCarbs || 0, goal: profile.carbsGoal || 250, color: 'bg-orange-500' },
                    { label: 'Fats', value: scan.fats, total: dailySummary?.totalFats || 0, goal: profile.fatsGoal || 70, color: 'bg-purple-500' },
                  ].map((item) => {
                    const scanPercentage = Math.round((item.value / item.goal) * 100);
                    const totalPercentage = Math.round((item.total / item.goal) * 100);
                    const previousPercentage = Math.round(((item.total - item.value) / item.goal) * 100);
                    
                    return (
                      <div key={item.label} className="space-y-3 px-2">
                        <div className="flex justify-between items-end">
                          <div className="space-y-0.5">
                            <span className="text-xs font-black text-gray-900 uppercase tracking-tight">{item.label}</span>
                            <p className="text-[10px] font-bold text-gray-400">
                              +{item.value}g {scanPercentage >= 20 ? 'significantly helps meet goal' : 'helps meet goal'}
                            </p>
                          </div>
                          <div className="text-right">
                            <span className={cn(
                              "text-sm font-black tracking-tight block",
                              totalPercentage >= 100 
                                ? (profile.goal === 'lose' ? "text-red-500" : "text-blue-600") 
                                : "text-green-600"
                            )}>
                              {totalPercentage}% of goal
                            </span>
                            <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">
                              {item.total} / {item.goal}g
                            </p>
                          </div>
                        </div>
                        <div className="h-3 bg-gray-100 rounded-full overflow-hidden border border-white/50 relative">
                          {/* Previous Total */}
                          <motion.div 
                            initial={{ width: 0 }}
                            animate={{ width: `${Math.min(previousPercentage, 100)}%` }}
                            className={cn("h-full absolute left-0 top-0 opacity-40", item.color)}
                          />
                          {/* Current Scan Contribution */}
                          <motion.div 
                            initial={{ width: `${Math.min(previousPercentage, 100)}%` }}
                            animate={{ width: `${Math.min(totalPercentage, 100)}%` }}
                            className={cn("h-full absolute left-0 top-0", item.color)}
                          >
                            <div className="absolute inset-0 bg-gradient-to-r from-white/20 to-transparent" />
                          </motion.div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </motion.div>
            )}
          </div>
        )}

        <div className="glass-card p-10 rounded-[48px] ios-shadow space-y-6 relative overflow-hidden">
          <div className="absolute top-0 right-0 p-8 opacity-[0.03] pointer-events-none">
            <Check size={120} className="text-green-600" />
          </div>
          <div className="flex items-center gap-3 relative z-10">
            <div className="w-10 h-10 bg-green-500/10 rounded-2xl flex items-center justify-center text-green-600">
              <Check size={20} strokeWidth={2.5} />
            </div>
            <h3 className="text-xl font-bold tracking-tight">AI Insight</h3>
          </div>
          <div className="text-gray-600 leading-relaxed font-medium relative z-10 text-lg">
            {(scan.type === 'food' || (scan.calories && scan.calories > 0)) ? (
              <>
                <span className="block mb-2">
                  This meal is {scan.protein > 20 ? 'excellent for muscle recovery due to its high protein content' : 'a balanced choice for your daily intake'}. 
                  {scan.calories > 800 ? ' It is quite calorie-dense, so consider balancing your next meal with lighter options.' : ' It fits perfectly within your daily calorie budget.'}
                </span>
                {personalizedTip && (
                  <span className="block p-4 bg-green-50/50 rounded-2xl border border-green-100 text-green-800 text-base italic">
                    💡 Tip: {personalizedTip}
                  </span>
                )}
              </>
            ) : (
              <div className="space-y-6">
                <div className="space-y-4">
                  <p className="font-medium text-gray-500 text-base">Our AI has analyzed this image and detected the following:</p>
                  <div className="grid grid-cols-1 gap-3">
                    {[
                      { 
                        label: 'Type', 
                        value: scan.type, 
                        color: 'bg-green-500', 
                        bgColor: 'bg-green-50/40',
                        icon: scan.type === 'person' ? User : scan.type === 'animal' ? Dog : Check 
                      },
                      { 
                        label: 'Details', 
                        value: scan.details || 'Unknown', 
                        color: 'bg-blue-500', 
                        bgColor: 'bg-blue-50/40',
                        icon: Info 
                      },
                      { 
                        label: 'Confidence', 
                        value: `${Math.round((scan.confidence || 0) * 100)}%`, 
                        color: 'bg-orange-500', 
                        bgColor: 'bg-orange-50/40',
                        icon: Flame 
                      }
                    ].map((item) => (
                      <div key={item.label} className={cn("flex items-center gap-4 p-4 backdrop-blur-md rounded-3xl border shadow-sm transition-all", item.bgColor, "border-white/60")}>
                        <div className={cn("w-10 h-10 rounded-2xl flex items-center justify-center text-white shadow-lg", item.color)}>
                          <item.icon size={18} strokeWidth={2.5} />
                        </div>
                        <div className="flex-1">
                          <p className="text-[10px] font-black uppercase tracking-[0.2em] text-gray-400 leading-none mb-1">{item.label}</p>
                          <p className="text-lg font-black text-gray-900 leading-none capitalize">{item.value}</p>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
                <div className="p-6 bg-white/30 backdrop-blur-sm rounded-[32px] border border-white/40 italic text-base leading-relaxed text-gray-600 shadow-inner">
                  "{scan.description}"
                </div>
                
                <button 
                  onClick={handleShare}
                  className="w-full py-4 bg-white/50 hover:bg-white/80 rounded-[24px] text-sm font-bold transition-all flex items-center justify-center gap-2 border border-white/60 text-gray-700 ios-tap"
                >
                  <Share2 size={18} strokeWidth={2.5} />
                  Share Detection
                </button>

                <p className="text-xs text-gray-400 font-bold leading-relaxed px-2">
                  NutriSnap is primarily designed for food tracking, but we use our advanced vision models to help you organize your entire health gallery.
                </p>
              </div>
            )}
          </div>
        </div>

        {(scan.type === 'food' || (scan.calories && scan.calories > 0)) && (
          <div className="space-y-4">
            <button 
              onClick={handleLogMeal}
              className="w-full bg-green-600 text-white py-6 rounded-[32px] font-black shadow-xl hover:bg-green-700 transition-all flex items-center justify-center gap-3 active:scale-[0.98] ios-shadow"
            >
              <Plus size={20} strokeWidth={2.5} />
              Log this Meal
            </button>
            
            <button 
              onClick={handleShare}
              className="w-full bg-white text-gray-900 py-6 rounded-[32px] font-black shadow-xl border border-gray-100 hover:bg-gray-50 transition-all flex items-center justify-center gap-3 active:scale-[0.98] ios-shadow"
            >
              <Share2 size={20} strokeWidth={2.5} />
              Share this Meal
            </button>
          </div>
        )}

        <button 
          onClick={() => {
            triggerHaptic(hapticPatterns.light);
            navigate('/');
          }}
          className="w-full bg-gray-900 text-white py-6 rounded-[32px] font-black shadow-2xl hover:bg-black transition-all flex items-center justify-center gap-3 active:scale-[0.98] ios-shadow"
        >
          Back to Dashboard
        </button>
      </div>
    </div>
  );
};

export default ResultScreen;
