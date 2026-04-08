import React from 'react';
import { TrendingUp, Calendar, PieChart, Activity, Apple, Zap, Droplets, Flame, ChevronRight, Info, Sparkles } from 'lucide-react';
import { motion } from 'motion/react';
import { useUser } from '../contexts/UserContext';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell, ComposedChart, Line, Legend } from 'recharts';
import { format, subDays, isSameDay } from 'date-fns';

const AnalyticsScreen: React.FC = () => {
  const { profile, dailySummary, scans } = useUser();

  const calorieProgress = profile ? (dailySummary?.totalCalories || 0) / (profile.calorieLimit || 2000) : 0;
  const waterProgress = profile ? (dailySummary?.totalWater || 0) / (profile.waterGoal || 2500) : 0;

  const macroData = [
    { label: 'Protein', value: dailySummary?.totalProtein || 0, goal: profile?.proteinGoal || 150, color: 'bg-blue-500', icon: Zap, unit: 'g', textColor: 'text-blue-500' },
    { label: 'Carbs', value: dailySummary?.totalCarbs || 0, goal: profile?.carbsGoal || 250, color: 'bg-orange-500', icon: Apple, unit: 'g', textColor: 'text-orange-500' },
    { label: 'Fats', value: dailySummary?.totalFats || 0, goal: profile?.fatsGoal || 70, color: 'bg-purple-500', icon: Droplets, unit: 'g', textColor: 'text-purple-500' },
  ];

  // Process last 7 days data
  const weeklyData = Array.from({ length: 7 }, (_, i) => {
    const date = subDays(new Date(), 6 - i);
    const dayScans = scans.filter(s => isSameDay(new Date(s.timestamp), date));
    
    return {
      name: format(date, 'EEE'),
      calories: dayScans.reduce((sum, s) => sum + (s.calories || 0), 0),
      protein: dayScans.reduce((sum, s) => sum + (s.protein || 0), 0),
      carbs: dayScans.reduce((sum, s) => sum + (s.carbs || 0), 0),
      fats: dayScans.reduce((sum, s) => sum + (s.fats || 0), 0),
      fullDate: format(date, 'MMM d'),
    };
  });

  return (
    <div className="space-y-10 pb-10">
      <div className="flex items-center justify-between px-2">
        <div className="flex items-center gap-2 glass px-4 py-2 rounded-2xl ios-shadow border border-white/50">
          <Calendar size={16} className="text-green-600" strokeWidth={2.5} />
          <span className="text-xs font-bold text-gray-600">Weekly Overview</span>
        </div>
        <button className="w-10 h-10 glass rounded-2xl flex items-center justify-center text-gray-400 ios-shadow ios-tap border border-white/50">
          <TrendingUp size={20} />
        </button>
      </div>

      {/* Daily Summary Overview */}
      <motion.div 
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="glass-card p-8 rounded-[40px] ios-shadow bg-gradient-to-br from-green-500 to-green-600 text-white space-y-6"
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Activity size={20} strokeWidth={2.5} />
            <h3 className="text-sm font-bold uppercase tracking-widest">Daily Summary</h3>
          </div>
          <span className="text-[10px] font-bold uppercase tracking-widest opacity-70">{format(new Date(), 'EEEE, MMM d')}</span>
        </div>

        <div className="grid grid-cols-2 gap-8">
          <div className="space-y-1">
            <p className="text-[10px] font-bold uppercase tracking-widest opacity-70">Calories</p>
            <div className="flex items-baseline gap-1">
              <span className="text-3xl font-black">{dailySummary?.totalCalories || 0}</span>
              <span className="text-xs font-bold opacity-70">/ {profile?.calorieLimit || 2000} kcal</span>
            </div>
          </div>
          <div className="space-y-1">
            <p className="text-[10px] font-bold uppercase tracking-widest opacity-70">Water</p>
            <div className="flex items-baseline gap-1">
              <span className="text-3xl font-black">{dailySummary?.totalWater || 0}</span>
              <span className="text-xs font-bold opacity-70">/ {profile?.waterGoal || 2500} ml</span>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-4 pt-4 border-t border-white/20">
          <div className="space-y-0.5">
            <p className="text-[8px] font-bold uppercase tracking-widest opacity-70">Protein</p>
            <p className="text-sm font-black">{dailySummary?.totalProtein || 0}g</p>
          </div>
          <div className="space-y-0.5">
            <p className="text-[8px] font-bold uppercase tracking-widest opacity-70">Carbs</p>
            <p className="text-sm font-black">{dailySummary?.totalCarbs || 0}g</p>
          </div>
          <div className="space-y-0.5">
            <p className="text-[8px] font-bold uppercase tracking-widest opacity-70">Fats</p>
            <p className="text-sm font-black">{dailySummary?.totalFats || 0}g</p>
          </div>
        </div>
      </motion.div>

      {/* Weekly Trend Chart - Enhanced */}
      <motion.div 
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="glass-card p-8 rounded-[40px] ios-shadow space-y-6"
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Activity className="text-green-500" size={18} strokeWidth={2.5} />
            <h3 className="text-sm font-bold text-gray-900 uppercase tracking-widest">Weekly Trends</h3>
          </div>
          <div className="flex gap-2">
            <div className="flex items-center gap-1">
              <div className="w-2 h-2 rounded-full bg-green-500" />
              <span className="text-[8px] font-bold text-gray-400 uppercase tracking-widest">Kcal</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="w-2 h-2 rounded-full bg-blue-500" />
              <span className="text-[8px] font-bold text-gray-400 uppercase tracking-widest">P</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="w-2 h-2 rounded-full bg-orange-500" />
              <span className="text-[8px] font-bold text-gray-400 uppercase tracking-widest">C</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="w-2 h-2 rounded-full bg-purple-500" />
              <span className="text-[8px] font-bold text-gray-400 uppercase tracking-widest">F</span>
            </div>
          </div>
        </div>

        <div className="h-64 w-full">
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={weeklyData}>
              <XAxis 
                dataKey="name" 
                axisLine={false} 
                tickLine={false} 
                tick={{ fontSize: 10, fontWeight: 700, fill: '#9CA3AF' }}
                dy={10}
              />
              <YAxis yAxisId="left" hide />
              <YAxis yAxisId="right" hide />
              <Tooltip 
                cursor={{ fill: 'rgba(0,0,0,0.02)' }}
                content={({ active, payload }) => {
                  if (active && payload && payload.length) {
                    const data = payload[0].payload;
                    const goals = {
                      calories: profile?.calorieLimit || 2000,
                      protein: profile?.proteinGoal || 150,
                      carbs: profile?.carbsGoal || 250,
                      fats: profile?.fatsGoal || 70
                    };

                    return (
                      <div className="glass p-4 rounded-2xl border border-white/50 shadow-xl space-y-3 min-w-[160px]">
                        <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest border-b border-gray-100 pb-2">{data.fullDate}</p>
                        
                        <div className="space-y-2">
                          <div className="flex items-center justify-between gap-4">
                            <span className="text-[10px] font-bold text-green-600 uppercase tracking-widest">Calories</span>
                            <div className="text-right">
                              <p className="text-sm font-black text-gray-900">{data.calories} kcal</p>
                              <p className="text-[8px] font-bold text-gray-400">{Math.round((data.calories / goals.calories) * 100)}% of goal</p>
                            </div>
                          </div>

                          <div className="grid grid-cols-3 gap-2 pt-2 border-t border-gray-50">
                            <div className="text-center">
                              <p className="text-[8px] font-bold text-blue-500 uppercase">Prot</p>
                              <p className="text-[10px] font-black text-gray-900">{data.protein}g</p>
                              <p className="text-[7px] font-bold text-gray-400">{Math.round((data.protein / goals.protein) * 100)}%</p>
                            </div>
                            <div className="text-center">
                              <p className="text-[8px] font-bold text-orange-500 uppercase">Carb</p>
                              <p className="text-[10px] font-black text-gray-900">{data.carbs}g</p>
                              <p className="text-[7px] font-bold text-gray-400">{Math.round((data.carbs / goals.carbs) * 100)}%</p>
                            </div>
                            <div className="text-center">
                              <p className="text-[8px] font-bold text-purple-500 uppercase">Fat</p>
                              <p className="text-[10px] font-black text-gray-900">{data.fats}g</p>
                              <p className="text-[7px] font-bold text-gray-400">{Math.round((data.fats / goals.fats) * 100)}%</p>
                            </div>
                          </div>
                        </div>
                      </div>
                    );
                  }
                  return null;
                }}
              />
              <Bar yAxisId="right" dataKey="protein" fill="#3B82F6" radius={[4, 4, 0, 0]} barSize={6} />
              <Bar yAxisId="right" dataKey="carbs" fill="#F97316" radius={[4, 4, 0, 0]} barSize={6} />
              <Bar yAxisId="right" dataKey="fats" fill="#A855F7" radius={[4, 4, 0, 0]} barSize={6} />
              <Line 
                yAxisId="left" 
                type="monotone" 
                dataKey="calories" 
                stroke="#22C55E" 
                strokeWidth={3} 
                dot={{ fill: '#22C55E', strokeWidth: 2, r: 4, stroke: '#fff' }}
                activeDot={{ r: 6, strokeWidth: 0 }}
              />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </motion.div>

      {/* Weekly Macro Progress Chart */}
      <motion.div 
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ delay: 0.1 }}
        className="glass-card p-8 rounded-[40px] ios-shadow space-y-6"
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Zap className="text-blue-500" size={18} strokeWidth={2.5} />
            <h3 className="text-sm font-bold text-gray-900 uppercase tracking-widest">Macro Progress</h3>
          </div>
          <div className="flex gap-3">
            <div className="flex items-center gap-1">
              <div className="w-2 h-2 rounded-full bg-blue-500" />
              <span className="text-[8px] font-bold text-gray-400 uppercase tracking-widest">P</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="w-2 h-2 rounded-full bg-orange-500" />
              <span className="text-[8px] font-bold text-gray-400 uppercase tracking-widest">C</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="w-2 h-2 rounded-full bg-purple-500" />
              <span className="text-[8px] font-bold text-gray-400 uppercase tracking-widest">F</span>
            </div>
          </div>
        </div>

        <div className="h-48 w-full">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={weeklyData} barGap={4}>
              <XAxis 
                dataKey="name" 
                axisLine={false} 
                tickLine={false} 
                tick={{ fontSize: 10, fontWeight: 700, fill: '#9CA3AF' }}
                dy={10}
              />
              <Tooltip 
                cursor={{ fill: 'rgba(0,0,0,0.02)' }}
                content={({ active, payload }) => {
                  if (active && payload && payload.length) {
                    return (
                      <div className="glass p-4 rounded-2xl border border-white/50 shadow-xl space-y-2 min-w-[140px]">
                        <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest mb-1">{payload[0].payload.fullDate}</p>
                        {payload.map((p: any) => {
                          const goal = p.name === 'protein' ? (profile?.proteinGoal || 150) : 
                                       p.name === 'carbs' ? (profile?.carbsGoal || 250) : 
                                       (profile?.fatsGoal || 70);
                          const percent = Math.round((p.value / goal) * 100);
                          
                          return (
                            <div key={p.name} className="flex flex-col gap-0.5">
                              <div className="flex items-center justify-between gap-4">
                                <span className="text-[10px] font-bold text-gray-500 uppercase tracking-widest">{p.name}</span>
                                <span className="text-sm font-black text-gray-900">{p.value}g</span>
                              </div>
                              <div className="h-1 bg-gray-100 rounded-full overflow-hidden">
                                <div 
                                  className={cn("h-full", p.fill)} 
                                  style={{ width: `${Math.min(percent, 100)}%` }} 
                                />
                              </div>
                              <span className="text-[8px] font-bold text-gray-400 text-right">{percent}% of goal</span>
                            </div>
                          );
                        })}
                      </div>
                    );
                  }
                  return null;
                }}
              />
              <Bar dataKey="protein" fill="#3B82F6" radius={[4, 4, 0, 0]} barSize={8} />
              <Bar dataKey="carbs" fill="#F97316" radius={[4, 4, 0, 0]} barSize={8} />
              <Bar dataKey="fats" fill="#A855F7" radius={[4, 4, 0, 0]} barSize={8} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </motion.div>

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

        {/* Water Intake Summary */}
        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="glass-card p-10 rounded-[48px] ios-shadow space-y-8 relative overflow-hidden"
        >
          <div className="absolute top-0 right-0 p-8 opacity-[0.03] pointer-events-none">
            <Droplets size={160} className="text-blue-600" />
          </div>

          <div className="flex items-center justify-between relative z-10">
            <div className="flex items-center gap-2">
              <Droplets className="text-blue-500" size={20} strokeWidth={2.5} />
              <h3 className="font-bold text-gray-900 tracking-tight">Hydration Progress</h3>
            </div>
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
                  animate={{ strokeDashoffset: 628.32 * (1 - Math.min(waterProgress, 1)) }}
                  strokeLinecap="round"
                  className="text-blue-500"
                />
              </svg>
              <div className="absolute inset-0 flex flex-col items-center justify-center text-center">
                <span className="text-5xl font-black text-gray-900 tracking-tighter">{dailySummary?.totalWater || 0}</span>
                <span className="text-[10px] font-black text-gray-400 uppercase tracking-[0.2em] mt-1">ml Consumed</span>
              </div>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-6 pt-8 border-t border-gray-100/50 relative z-10">
            <div className="text-center space-y-1">
              <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest">Goal</p>
              <p className="text-2xl font-black text-gray-900 tracking-tight">{profile?.waterGoal || 2500}</p>
            </div>
            <div className="text-center border-l border-gray-100/50 space-y-1">
              <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest">Remaining</p>
              <p className="text-2xl font-black text-blue-600 tracking-tight">
                {Math.max(0, (profile?.waterGoal || 2500) - (dailySummary?.totalWater || 0))}
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
        <div className="glass-card p-10 rounded-[48px] ios-shadow space-y-8 relative overflow-hidden bg-slate-900 text-white border border-slate-800">
          <div className="absolute top-0 right-0 p-8 opacity-[0.1] pointer-events-none">
            <Sparkles size={120} className="text-green-400" />
          </div>

          <div className="flex items-center gap-3 relative z-10">
            <div className="w-10 h-10 bg-green-500/20 rounded-2xl flex items-center justify-center text-green-400 border border-green-500/20">
              <Sparkles size={20} strokeWidth={2.5} />
            </div>
            <h3 className="text-2xl font-black tracking-tight">AI Health Insights</h3>
          </div>
          
          <div className="space-y-6 relative z-10">
            <div className="flex gap-5 group">
              <div className="w-1.5 h-auto bg-green-500 rounded-full opacity-40 group-hover:opacity-100 transition-opacity" />
              <p className="text-base text-slate-200 leading-relaxed font-semibold">
                {calorieProgress > 0.8 
                  ? "You're approaching your calorie limit. Opt for high-volume, low-calorie snacks like cucumber or berries."
                  : "Excellent pace! You're perfectly aligned with your daily calorie targets."}
              </p>
            </div>
            <div className="flex gap-5 group">
              <div className="w-1.5 h-auto bg-blue-500 rounded-full opacity-40 group-hover:opacity-100 transition-opacity" />
              <p className="text-base text-slate-200 leading-relaxed font-semibold">
                {dailySummary && dailySummary.totalProtein < 50 
                  ? "Protein intake is slightly behind. Consider a Greek yogurt or protein shake to recover."
                  : "Protein levels are optimal. This is great for muscle maintenance and satiety."}
              </p>
            </div>
          </div>

          <button className="w-full py-5 bg-white/5 hover:bg-white/10 rounded-[24px] text-sm font-black transition-all flex items-center justify-center gap-3 border border-white/10 relative z-10 uppercase tracking-widest">
            View Detailed Report 
            <ChevronRight size={18} strokeWidth={3} />
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
