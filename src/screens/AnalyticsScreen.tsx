import React from 'react';
import { TrendingUp, Calendar, PieChart, Activity, Apple, Zap, Droplets, Flame, ChevronRight, Info, Sparkles } from 'lucide-react';
import { motion } from 'motion/react';
import { useUser } from '../contexts/UserContext';

const AnalyticsScreen: React.FC = () => {
  const { profile, dailySummary } = useUser();

  const calorieProgress = profile ? (dailySummary?.totalCalories || 0) / profile.calorieLimit : 0;

  const macroData = [
    { label: 'Protein', value: dailySummary?.totalProtein || 0, goal: 150, color: 'bg-blue-500', icon: Zap, unit: 'g', textColor: 'text-blue-500' },
    { label: 'Carbs', value: dailySummary?.totalCarbs || 0, goal: 250, color: 'bg-orange-500', icon: Apple, unit: 'g', textColor: 'text-orange-500' },
    { label: 'Fats', value: dailySummary?.totalFats || 0, goal: 70, color: 'bg-purple-500', icon: Droplets, unit: 'g', textColor: 'text-purple-500' },
  ];

  return (
    <div className="space-y-10 pb-10">
      <div className="flex items-center justify-between px-2">
        <div className="flex items-center gap-2 glass px-4 py-2 rounded-2xl ios-shadow">
          <Calendar size={16} className="text-green-600" strokeWidth={2.5} />
          <span className="text-xs font-bold text-gray-600">Today</span>
        </div>
        <button className="w-10 h-10 glass rounded-2xl flex items-center justify-center text-gray-400 ios-shadow ios-tap">
          <TrendingUp size={20} />
        </button>
      </div>

      {/* Main Stats Grid */}
      <div className="grid grid-cols-1 gap-8">
        {/* Calorie Summary */}
        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="glass-card p-10 rounded-[48px] shadow-sm ios-shadow space-y-8 relative overflow-hidden"
        >
          <div className="absolute top-0 right-0 p-8 opacity-[0.03] pointer-events-none">
            <PieChart size={160} className="text-green-600" />
          </div>

          <div className="flex items-center justify-between relative z-10">
            <div className="flex items-center gap-2">
              <Flame className="text-orange-500" size={20} strokeWidth={2.5} />
              <h3 className="font-bold text-gray-900 tracking-tight">Calorie Balance</h3>
            </div>
            <button className="text-gray-400 hover:text-gray-600 transition-colors">
              <Info size={18} strokeWidth={2.5} />
            </button>
          </div>

          <div className="flex items-center justify-center py-6 relative z-10">
            <div className="relative w-56 h-56">
              <svg className="w-full h-full transform -rotate-90">
                <circle
                  cx="112"
                  cy="112"
                  r="100"
                  stroke="currentColor"
                  strokeWidth="16"
                  fill="transparent"
                  className="text-gray-100/50"
                />
                <motion.circle
                  cx="112"
                  cy="112"
                  r="100"
                  stroke="currentColor"
                  strokeWidth="16"
                  fill="transparent"
                  strokeDasharray={628.32}
                  initial={{ strokeDashoffset: 628.32 }}
                  animate={{ strokeDashoffset: 628.32 * (1 - Math.min(calorieProgress, 1)) }}
                  strokeLinecap="round"
                  className={calorieProgress > 1 ? "text-red-500" : "text-green-500"}
                />
              </svg>
              <div className="absolute inset-0 flex flex-col items-center justify-center text-center">
                <span className="text-5xl font-black text-gray-900 tracking-tighter">{dailySummary?.totalCalories || 0}</span>
                <span className="text-[10px] font-black text-gray-400 uppercase tracking-[0.2em] mt-1">Consumed</span>
              </div>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-6 pt-8 border-t border-gray-100/50 relative z-10">
            <div className="text-center space-y-1">
              <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest">Goal</p>
              <p className="text-2xl font-black text-gray-900 tracking-tight">{profile?.calorieLimit || 2000}</p>
            </div>
            <div className="text-center border-l border-gray-100/50 space-y-1">
              <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest">Remaining</p>
              <p className={cn(
                "text-2xl font-black tracking-tight",
                (profile?.calorieLimit || 2000) - (dailySummary?.totalCalories || 0) < 0 ? "text-red-500" : "text-green-600"
              )}>
                {Math.max(0, (profile?.calorieLimit || 2000) - (dailySummary?.totalCalories || 0))}
              </p>
            </div>
          </div>
        </motion.div>

        {/* Macros Breakdown */}
        <div className="space-y-6">
          <h3 className="text-[10px] font-bold uppercase tracking-[0.2em] text-gray-400 px-2">Macronutrients</h3>
          <div className="grid grid-cols-1 gap-4">
            {macroData.map((macro, idx) => (
              <motion.div 
                key={macro.label}
                initial={{ opacity: 0, x: -20 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: idx * 0.1 }}
                className="glass-card p-6 rounded-[32px] ios-shadow space-y-5"
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <div className={cn("w-12 h-12 rounded-2xl flex items-center justify-center text-white shadow-xl", macro.color)}>
                      <macro.icon size={24} strokeWidth={2.5} />
                    </div>
                    <div>
                      <h4 className="font-bold text-gray-900 text-lg tracking-tight">{macro.label}</h4>
                      <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">Target: {macro.goal}{macro.unit}</p>
                    </div>
                  </div>
                  <div className="text-right">
                    <span className="text-2xl font-black text-gray-900 tracking-tight">{macro.value}</span>
                    <span className="text-xs font-bold text-gray-400 ml-1">{macro.unit}</span>
                  </div>
                </div>
                <div className="h-2 bg-gray-100/50 rounded-full overflow-hidden border border-white/20">
                  <motion.div 
                    initial={{ width: 0 }}
                    animate={{ width: `${Math.min((macro.value / macro.goal) * 100, 100)}%` }}
                    className={cn("h-full rounded-full", macro.color)}
                  />
                </div>
              </motion.div>
            ))}
          </div>
        </div>

        {/* Health Insights */}
        <div className="glass-card p-10 rounded-[48px] ios-shadow space-y-8 relative overflow-hidden bg-gray-900 text-white">
          <div className="absolute top-0 right-0 p-8 opacity-[0.05] pointer-events-none">
            <Sparkles size={120} className="text-green-400" />
          </div>

          <div className="flex items-center gap-3 relative z-10">
            <div className="w-8 h-8 bg-green-500/20 rounded-xl flex items-center justify-center text-green-400">
              <Sparkles size={18} strokeWidth={2.5} />
            </div>
            <h3 className="text-xl font-bold tracking-tight">AI Health Insights</h3>
          </div>
          
          <div className="space-y-6 relative z-10">
            <div className="flex gap-5">
              <div className="w-1.5 h-auto bg-green-500 rounded-full opacity-50" />
              <p className="text-sm text-gray-300 leading-relaxed font-medium">
                {calorieProgress > 0.8 
                  ? "You're approaching your calorie limit. Opt for high-volume, low-calorie snacks like cucumber or berries."
                  : "Excellent pace! You're perfectly aligned with your daily calorie targets."}
              </p>
            </div>
            <div className="flex gap-5">
              <div className="w-1.5 h-auto bg-blue-500 rounded-full opacity-50" />
              <p className="text-sm text-gray-300 leading-relaxed font-medium">
                {dailySummary && dailySummary.totalProtein < 50 
                  ? "Protein intake is slightly behind. Consider a Greek yogurt or protein shake to recover."
                  : "Protein levels are optimal. This is great for muscle maintenance and satiety."}
              </p>
            </div>
          </div>

          <button className="w-full py-5 bg-white/10 hover:bg-white/20 rounded-[24px] text-sm font-bold transition-all flex items-center justify-center gap-3 border border-white/10 relative z-10">
            View Detailed Report 
            <ChevronRight size={18} strokeWidth={2.5} />
          </button>
        </div>
      </div>
    </div>
  );
};

function cn(...inputs: any[]) {
  return inputs.filter(Boolean).join(' ');
}

export default AnalyticsScreen;
