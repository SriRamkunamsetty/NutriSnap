import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  Flame, 
  Footprints, 
  Droplets, 
  Moon, 
  HeartPulse, 
  Sparkles, 
  Plus, 
  Minus, 
  ChevronRight, 
  UtensilsCrossed, 
  Zap,
  CheckCircle2,
  AlertCircle
} from 'lucide-react';
import { useUser } from '../contexts/UserContext';
import { updateWaterIntake, saveDailySummary, getDailySummaryOnce } from '../services/storageService';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';

interface DailyContextPanelsProps {
  onOpenMessOS?: () => void;
  onOpenQuickLog?: () => void;
}

export const DailyContextPanels: React.FC<DailyContextPanelsProps> = ({ 
  onOpenMessOS,
  onOpenQuickLog 
}) => {
  const { profile, dailySummary } = useUser();
  const [isUpdating, setIsUpdating] = useState(false);

  const stepsGoal = 8000;
  const currentSteps = dailySummary?.totalSteps || 4850;
  const stepsPct = Math.min(100, Math.round((currentSteps / stepsGoal) * 100));
  const activeCalories = Math.round(currentSteps * 0.04); // ~0.04 kcal per step
  const distanceKm = (currentSteps * 0.00078).toFixed(2); // ~0.78m per step

  const waterGoal = profile?.waterGoal || 2500;
  const currentWater = dailySummary?.totalWater || 1500;
  const waterPct = Math.min(100, Math.round((currentWater / waterGoal) * 100));

  // Quick step adder
  const handleAddSteps = async (amount: number) => {
    setIsUpdating(true);
    triggerHaptic(hapticPatterns.light);
    try {
      const summary = await getDailySummaryOnce();
      const newSteps = (summary.totalSteps || 0) + amount;
      await saveDailySummary({
        totalSteps: newSteps,
      });
    } catch (e) {
      console.error('Failed to update steps', e);
    } finally {
      setIsUpdating(false);
    }
  };

  // Quick water adjuster
  const handleAdjustWater = async (amount: number) => {
    setIsUpdating(true);
    triggerHaptic(hapticPatterns.light);
    try {
      const newAmount = Math.max(0, currentWater + amount);
      await updateWaterIntake(newAmount);
    } catch (e) {
      console.error('Failed to update water', e);
    } finally {
      setIsUpdating(false);
    }
  };

  return (
    <div className="space-y-4">
      {/* 2-Column Grid for Move & Hydrate */}
      <div className="grid grid-cols-2 gap-3.5">
        {/* PANEL 1: MOVE */}
        <motion.div
          id="panel-move"
          whileHover={{ y: -2 }}
          className="glass-card p-4 rounded-[28px] border border-white/80 bg-white/90 shadow-sm flex flex-col justify-between relative overflow-hidden"
        >
          <div className="flex items-center justify-between">
            <div className="w-8 h-8 rounded-xl bg-orange-50 text-orange-600 flex items-center justify-center">
              <Footprints size={17} />
            </div>
            <span className="text-[10px] font-black tracking-wider text-orange-700 bg-orange-50/80 px-2 py-0.5 rounded-full">
              {stepsPct}%
            </span>
          </div>

          <div className="my-2.5">
            <span className="text-[10px] font-bold text-gray-400 uppercase tracking-wider block">
              Move & Steps
            </span>
            <div className="text-xl font-black text-gray-900 tracking-tight">
              {currentSteps.toLocaleString()}{' '}
              <span className="text-xs font-semibold text-gray-400">/ {stepsGoal.toLocaleString()}</span>
            </div>
            <div className="flex items-center gap-2 mt-1 text-[11px] font-semibold text-gray-500">
              <span>{activeCalories} kcal</span>
              <span>•</span>
              <span>{distanceKm} km</span>
            </div>
          </div>

          {/* Steps Progress Bar */}
          <div className="w-full bg-orange-100/60 h-2 rounded-full overflow-hidden mb-2.5">
            <div 
              className="h-full bg-gradient-to-r from-orange-400 to-amber-500 rounded-full transition-all duration-500"
              style={{ width: `${stepsPct}%` }}
            />
          </div>

          <button
            onClick={() => handleAddSteps(500)}
            disabled={isUpdating}
            className="w-full py-1.5 px-2 bg-orange-50 hover:bg-orange-100 text-orange-700 rounded-xl text-xs font-bold flex items-center justify-center gap-1 transition-colors"
          >
            <Plus size={13} strokeWidth={3} />
            <span>500 steps</span>
          </button>
        </motion.div>

        {/* PANEL 2: HYDRATE */}
        <motion.div
          id="panel-hydrate"
          whileHover={{ y: -2 }}
          className="glass-card p-4 rounded-[28px] border border-white/80 bg-white/90 shadow-sm flex flex-col justify-between relative overflow-hidden"
        >
          <div className="flex items-center justify-between">
            <div className="w-8 h-8 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center">
              <Droplets size={17} />
            </div>
            <span className="text-[10px] font-black tracking-wider text-blue-700 bg-blue-50/80 px-2 py-0.5 rounded-full">
              {waterPct}%
            </span>
          </div>

          <div className="my-2.5">
            <span className="text-[10px] font-bold text-gray-400 uppercase tracking-wider block">
              Hydration
            </span>
            <div className="text-xl font-black text-gray-900 tracking-tight">
              {(currentWater / 1000).toFixed(1)}L{' '}
              <span className="text-xs font-semibold text-gray-400">/ {(waterGoal / 1000).toFixed(1)}L</span>
            </div>
            <p className="text-[11px] font-semibold text-gray-500 mt-1">
              {Math.max(0, waterGoal - currentWater)} ml remaining
            </p>
          </div>

          {/* Water Progress Bar */}
          <div className="w-full bg-blue-100/60 h-2 rounded-full overflow-hidden mb-2.5">
            <div 
              className="h-full bg-gradient-to-r from-blue-400 to-cyan-500 rounded-full transition-all duration-500"
              style={{ width: `${waterPct}%` }}
            />
          </div>

          <div className="flex gap-1.5">
            <button
              onClick={() => handleAdjustWater(-250)}
              disabled={isUpdating || currentWater <= 0}
              className="w-8 py-1.5 bg-blue-50 hover:bg-blue-100 disabled:opacity-40 text-blue-700 rounded-xl text-xs font-bold flex items-center justify-center transition-colors shrink-0"
            >
              <Minus size={13} strokeWidth={3} />
            </button>
            <button
              onClick={() => handleAdjustWater(250)}
              disabled={isUpdating}
              className="flex-1 py-1.5 bg-blue-50 hover:bg-blue-100 text-blue-700 rounded-xl text-xs font-bold flex items-center justify-center gap-1 transition-colors"
            >
              <Plus size={13} strokeWidth={3} />
              <span>250 ml</span>
            </button>
          </div>
        </motion.div>
      </div>

      {/* 2-Column Grid for Rest & Recovery */}
      <div className="grid grid-cols-2 gap-3.5">
        {/* PANEL 3: REST */}
        <div 
          id="panel-rest"
          className="glass-card p-4 rounded-[28px] border border-white/80 bg-white/90 shadow-sm space-y-2"
        >
          <div className="flex items-center justify-between">
            <div className="w-8 h-8 rounded-xl bg-indigo-50 text-indigo-600 flex items-center justify-center">
              <Moon size={17} />
            </div>
            <span className="text-[10px] font-black text-indigo-700 bg-indigo-50 px-2 py-0.5 rounded-full">
              Score 88
            </span>
          </div>
          <div>
            <span className="text-[10px] font-bold text-gray-400 uppercase tracking-wider block">
              Sleep & Rest
            </span>
            <div className="text-xl font-black text-gray-900 tracking-tight">
              7h 24m
            </div>
            <p className="text-[11px] font-semibold text-emerald-600 flex items-center gap-1 mt-0.5">
              <CheckCircle2 size={12} /> Optimal deep cycle
            </p>
          </div>
        </div>

        {/* PANEL 4: RECOVERY */}
        <div 
          id="panel-recovery"
          className="glass-card p-4 rounded-[28px] border border-white/80 bg-white/90 shadow-sm space-y-2"
        >
          <div className="flex items-center justify-between">
            <div className="w-8 h-8 rounded-xl bg-rose-50 text-rose-600 flex items-center justify-center">
              <HeartPulse size={17} />
            </div>
            <span className="text-[10px] font-black text-rose-700 bg-rose-50 px-2 py-0.5 rounded-full">
              High
            </span>
          </div>
          <div>
            <span className="text-[10px] font-bold text-gray-400 uppercase tracking-wider block">
              Resting Heart
            </span>
            <div className="text-xl font-black text-gray-900 tracking-tight">
              64 <span className="text-xs font-semibold text-gray-400">bpm</span>
            </div>
            <p className="text-[11px] font-semibold text-gray-500 mt-0.5">
              HRV 58ms • Ready to train
            </p>
          </div>
        </div>
      </div>

      {/* MessOS Hostel / Campus Food Shortcut */}
      {profile?.isHostelUser && onOpenMessOS && (
        <motion.div
          whileHover={{ scale: 1.01 }}
          onClick={onOpenMessOS}
          className="p-4 rounded-[26px] bg-gradient-to-r from-emerald-600 to-teal-700 text-white shadow-lg shadow-emerald-600/20 cursor-pointer flex items-center justify-between"
        >
          <div className="flex items-center gap-3.5">
            <div className="w-10 h-10 rounded-2xl bg-white/20 flex items-center justify-center text-white backdrop-blur-sm">
              <UtensilsCrossed size={20} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h4 className="text-sm font-bold">MessOS Campus Intelligence</h4>
                <span className="text-[9px] font-black uppercase tracking-wider bg-white/25 px-2 py-0.5 rounded-full">
                  Hostel Active
                </span>
              </div>
              <p className="text-xs text-white/80">
                Today's lunch hacks, high-protein mess swaps & timings
              </p>
            </div>
          </div>
          <ChevronRight size={18} className="text-white/70" />
        </motion.div>
      )}
    </div>
  );
};
