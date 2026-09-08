import React from 'react';
import { Flame, AlertTriangle, CheckCircle2, Zap, Wheat, Droplets } from 'lucide-react';
import { motion } from 'motion/react';
import { DailySummary, UserProfile } from '../types';

interface CalorieProgressRingProps {
  dailySummary?: DailySummary | null;
  profile?: UserProfile | null;
  calorieProgress: number;
}

export const CalorieProgressRing: React.FC<CalorieProgressRingProps> = ({
  dailySummary,
  profile,
  calorieProgress,
}) => {
  const consumed = dailySummary?.totalCalories || 0;
  const target = profile?.calorieLimit || 2000;
  const remaining = Math.max(0, target - consumed);
  const isOver = consumed > target;
  const overAmount = isOver ? consumed - target : 0;
  const pct = Math.round(calorieProgress * 100);

  // SVG Radial Ring Dimensions
  const size = 124;
  const strokeWidth = 11;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const clampedProgress = Math.min(Math.max(calorieProgress, 0), 1);
  const strokeDashoffset = circumference - clampedProgress * circumference;

  const gradientId = 'calorieProgressRingGradient';
  const startColor = isOver ? '#F87171' : calorieProgress >= 0.85 ? '#FBBF24' : '#34D399';
  const stopColor = isOver ? '#DC2626' : calorieProgress >= 0.85 ? '#D97706' : '#059669';

  return (
    <motion.div
      id="calorie-progress-card"
      initial={{ opacity: 0, scale: 0.96 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.4, ease: 'easeOut' }}
      className="glass-card p-6 sm:p-7 rounded-[36px] relative overflow-hidden ios-shadow space-y-5 bg-white/95"
    >
      <div className="absolute -top-10 -right-10 opacity-[0.03] pointer-events-none">
        <Flame size={220} className="text-emerald-600" />
      </div>

      {/* Top Header */}
      <div className="flex items-center justify-between relative z-10">
        <div className="flex items-center gap-2">
          <div
            className="w-2.5 h-2.5 rounded-full animate-pulse"
            style={{ backgroundColor: stopColor }}
          />
          <h2 className="text-[11px] font-black text-gray-400 uppercase tracking-widest">
            Daily Calorie Fuel
          </h2>
        </div>
        <span
          className={`text-xs font-black px-3 py-1 rounded-full border shadow-sm ${
            isOver
              ? 'bg-red-50 text-red-700 border-red-200'
              : calorieProgress >= 0.85
              ? 'bg-amber-50 text-amber-800 border-amber-200'
              : 'bg-emerald-50 text-emerald-700 border-emerald-200'
          }`}
        >
          {isOver ? `+${overAmount} kcal over` : `${pct}% of goal`}
        </span>
      </div>

      {/* Circular Progress Indicator & Numerical Highlights */}
      <div className="flex items-center gap-6 relative z-10">
        {/* SVG Circular Progress Ring */}
        <div className="relative w-[124px] h-[124px] flex-shrink-0 flex items-center justify-center">
          <svg width={size} height={size} className="transform -rotate-90">
            <defs>
              <linearGradient id={gradientId} x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stopColor={startColor} />
                <stop offset="100%" stopColor={stopColor} />
              </linearGradient>
            </defs>

            {/* Background Track Circle */}
            <circle
              cx={size / 2}
              cy={size / 2}
              r={radius}
              stroke="#F3F4F6"
              strokeWidth={strokeWidth}
              fill="transparent"
            />

            {/* Animated Progress Circle with Smooth Load Animation */}
            <motion.circle
              cx={size / 2}
              cy={size / 2}
              r={radius}
              stroke={`url(#${gradientId})`}
              strokeWidth={strokeWidth}
              strokeDasharray={circumference}
              initial={{ strokeDashoffset: circumference }}
              animate={{ strokeDashoffset }}
              transition={{ duration: 1.3, ease: [0.16, 1, 0.3, 1] }}
              strokeLinecap="round"
              fill="transparent"
            />
          </svg>

          {/* Center Info in Ring */}
          <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
            {isOver ? (
              <AlertTriangle size={20} className="text-red-500 mb-0.5 animate-bounce" />
            ) : (
              <Flame size={20} className="text-emerald-500 fill-emerald-500 mb-0.5" />
            )}
            <span
              className={`text-lg font-black tracking-tight ${
                isOver ? 'text-red-600' : 'text-gray-900'
              }`}
            >
              {pct}%
            </span>
            <span className="text-[9px] font-bold text-gray-400 uppercase tracking-widest">
              Goal
            </span>
          </div>
        </div>

        {/* Consumed vs Goal Metrics */}
        <div className="flex-1 space-y-2.5">
          <div>
            <p className="text-[10px] font-black text-gray-400 uppercase tracking-widest">
              Total Intake
            </p>
            <div className="flex items-baseline gap-1.5 mt-0.5">
              <span className="text-4xl font-black text-gray-900 tracking-tight">
                {consumed}
              </span>
              <span className="text-gray-400 font-bold text-xs tracking-tight">
                / {target} kcal
              </span>
            </div>
          </div>

          <div
            className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold border ${
              isOver
                ? 'bg-red-50 text-red-700 border-red-200'
                : 'bg-emerald-50 text-emerald-800 border-emerald-200'
            }`}
          >
            {isOver ? (
              <AlertTriangle size={13} className="text-red-500" />
            ) : (
              <CheckCircle2 size={13} className="text-emerald-600" />
            )}
            <span>
              {isOver
                ? `Exceeded by ${overAmount} kcal`
                : `${remaining} kcal remaining`}
            </span>
          </div>
        </div>
      </div>

      {/* Target Progress Bar */}
      <div className="space-y-1.5 relative z-10 pt-1">
        <div className="flex items-center justify-between text-[10px] font-black text-gray-400 uppercase tracking-widest px-0.5">
          <span>Daily Energy Gauge</span>
          <span>{clampedProgress >= 1 ? 'Target Reached' : `${target - consumed} kcal to goal`}</span>
        </div>
        <div className="h-2.5 bg-gray-100 rounded-full overflow-hidden border border-gray-100/60">
          <motion.div
            initial={{ width: 0 }}
            animate={{ width: `${Math.min(clampedProgress * 100, 100)}%` }}
            transition={{ duration: 1.1, ease: 'easeOut' }}
            className="h-full rounded-full transition-colors"
            style={{ backgroundColor: stopColor }}
          />
        </div>
      </div>

      {/* Macronutrient Breakdown */}
      <div className="grid grid-cols-3 gap-2.5 pt-1 relative z-10">
        {[
          {
            label: 'Protein',
            value: dailySummary?.totalProtein || 0,
            goal: profile?.proteinGoal || 150,
            icon: Zap,
            color: 'text-blue-600',
            barColor: 'bg-blue-500',
            bg: 'bg-blue-50/70',
            border: 'border-blue-100',
          },
          {
            label: 'Carbs',
            value: dailySummary?.totalCarbs || 0,
            goal: profile?.carbsGoal || 200,
            icon: Wheat,
            color: 'text-orange-600',
            barColor: 'bg-orange-500',
            bg: 'bg-orange-50/70',
            border: 'border-orange-100',
          },
          {
            label: 'Fats',
            value: dailySummary?.totalFats || 0,
            goal: profile?.fatsGoal || 70,
            icon: Droplets,
            color: 'text-purple-600',
            barColor: 'bg-purple-500',
            bg: 'bg-purple-50/70',
            border: 'border-purple-100',
          },
        ].map((macro) => {
          const macroPct = macro.goal > 0 ? Math.min((macro.value / macro.goal) * 100, 100) : 0;
          return (
            <div
              key={macro.label}
              className={`${macro.bg} p-2.5 sm:p-3 rounded-2xl border ${macro.border} space-y-1.5 shadow-sm`}
            >
              <div className="flex items-center gap-1.5">
                <macro.icon size={12} className={macro.color} />
                <span
                  className={`text-[9px] font-black uppercase tracking-wider ${macro.color}`}
                >
                  {macro.label}
                </span>
              </div>
              <div className="flex items-baseline gap-1">
                <span className="text-sm sm:text-base font-black text-gray-900">
                  {macro.value}
                </span>
                <span className="text-[10px] text-gray-400 font-bold">
                  /{macro.goal}g
                </span>
              </div>
              <div className="h-1.5 bg-gray-200/80 rounded-full overflow-hidden">
                <motion.div
                  initial={{ width: 0 }}
                  animate={{ width: `${macroPct}%` }}
                  transition={{ duration: 1, ease: 'easeOut' }}
                  className={`h-full ${macro.barColor} rounded-full`}
                />
              </div>
            </div>
          );
        })}
      </div>
    </motion.div>
  );
};
