import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronRight, ChevronLeft, User, Ruler, Weight, Target, Zap, Check, Loader2 } from 'lucide-react';
import { useUser } from '../contexts/UserContext';
import { saveUserProfile } from '../services/storageService';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { Goal } from '../types';

const OnboardingScreen: React.FC = () => {
  const navigate = useNavigate();
  const { profile, refreshProfile } = useUser();
  const [step, setStep] = useState(1);
  const [isSaving, setIsSaving] = useState(false);

  // Form state
  const [name, setName] = useState(profile?.displayName || '');
  const [height, setHeight] = useState(profile?.height || 175);
  const [weight, setWeight] = useState(profile?.weight || 70);
  const [goal, setGoal] = useState<Goal>(profile?.goal || 'maintain');
  const [calorieLimit, setCalorieLimit] = useState(profile?.calorieLimit || 2000);
  const [proteinGoal, setProteinGoal] = useState(profile?.proteinGoal || 150);
  const [carbsGoal, setCarbsGoal] = useState(profile?.carbsGoal || 250);
  const [fatsGoal, setFatsGoal] = useState(profile?.fatsGoal || 70);

  const totalSteps = 5;

  const handleNext = () => {
    if (step < totalSteps) {
      triggerHaptic(hapticPatterns.light);
      setStep(step + 1);
    } else {
      handleComplete();
    }
  };

  const handleBack = () => {
    if (step > 1) {
      triggerHaptic(hapticPatterns.light);
      setStep(step - 1);
    }
  };

  const handleComplete = async () => {
    setIsSaving(true);
    triggerHaptic(hapticPatterns.medium);
    
    try {
      // Calculate BMI
      const heightInMeters = height / 100;
      const bmi = weight / (heightInMeters * heightInMeters);
      
      await saveUserProfile({
        displayName: name,
        height,
        weight,
        bmi: parseFloat(bmi.toFixed(1)),
        goal,
        calorieLimit,
        proteinGoal,
        carbsGoal,
        fatsGoal,
        hasCompletedOnboarding: true
      });

      await refreshProfile();
      triggerHaptic(hapticPatterns.success);
      navigate('/');
    } catch (error) {
      console.error("Failed to save onboarding profile", error);
      triggerHaptic(hapticPatterns.error);
    } finally {
      setIsSaving(false);
    }
  };

  const updateSuggestedMacros = (newGoal: Goal, calories: number) => {
    let p = 150;
    let c = 250;
    let f = 70;

    if (newGoal === 'lose') {
      p = Math.round(weight * 2.2);
      f = Math.round((calories * 0.25) / 9);
      c = Math.round((calories - (p * 4) - (f * 9)) / 4);
    } else if (newGoal === 'gain') {
      p = Math.round(weight * 2);
      f = Math.round((calories * 0.25) / 9);
      c = Math.round((calories - (p * 4) - (f * 9)) / 4);
    } else {
      p = Math.round(weight * 1.8);
      f = Math.round((calories * 0.3) / 9);
      c = Math.round((calories - (p * 4) - (f * 9)) / 4);
    }

    setProteinGoal(p);
    setCarbsGoal(c);
    setFatsGoal(f);
  };

  const updateSuggestedCalories = (newGoal: Goal) => {
    let base = 2000;
    if (newGoal === 'lose') base = 1700;
    if (newGoal === 'gain') base = 2500;
    setCalorieLimit(base);
    updateSuggestedMacros(newGoal, base);
  };

  const renderStep = () => {
    switch (step) {
      case 1:
        return (
          <motion.div 
            key="step1"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-8"
          >
            <div className="space-y-2">
              <h2 className="text-3xl font-black text-gray-900 tracking-tight">What should we call you?</h2>
              <p className="text-gray-500 font-medium">This is how you'll appear in your health dashboard.</p>
            </div>
            <div className="relative">
              <User className="absolute left-5 top-1/2 -translate-y-1/2 text-gray-400" size={20} />
              <input 
                type="text" 
                placeholder="Your Name" 
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="w-full glass rounded-[24px] py-6 pl-14 pr-6 text-lg font-bold focus:outline-none focus:ring-4 focus:ring-green-500/10 transition-all ios-shadow"
              />
            </div>
          </motion.div>
        );
      case 2:
        return (
          <motion.div 
            key="step2"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-8"
          >
            <div className="space-y-2">
              <h2 className="text-3xl font-black text-gray-900 tracking-tight">Your Body Stats</h2>
              <p className="text-gray-500 font-medium">We use these to calculate your BMI and nutritional needs.</p>
            </div>
            <div className="grid grid-cols-1 gap-6">
              <div className="space-y-3">
                <label className="text-[10px] font-black uppercase tracking-widest text-gray-400 ml-4">Height (cm)</label>
                <div className="relative">
                  <Ruler className="absolute left-5 top-1/2 -translate-y-1/2 text-gray-400" size={20} />
                  <input 
                    type="number" 
                    value={height}
                    onChange={(e) => setHeight(parseInt(e.target.value))}
                    className="w-full glass rounded-[24px] py-6 pl-14 pr-6 text-lg font-bold focus:outline-none focus:ring-4 focus:ring-green-500/10 transition-all ios-shadow"
                  />
                </div>
              </div>
              <div className="space-y-3">
                <label className="text-[10px] font-black uppercase tracking-widest text-gray-400 ml-4">Weight (kg)</label>
                <div className="relative">
                  <Weight className="absolute left-5 top-1/2 -translate-y-1/2 text-gray-400" size={20} />
                  <input 
                    type="number" 
                    value={weight}
                    onChange={(e) => setWeight(parseInt(e.target.value))}
                    className="w-full glass rounded-[24px] py-6 pl-14 pr-6 text-lg font-bold focus:outline-none focus:ring-4 focus:ring-green-500/10 transition-all ios-shadow"
                  />
                </div>
              </div>
            </div>
          </motion.div>
        );
      case 3:
        return (
          <motion.div 
            key="step3"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-8"
          >
            <div className="space-y-2">
              <h2 className="text-3xl font-black text-gray-900 tracking-tight">What's your goal?</h2>
              <p className="text-gray-500 font-medium">Choose the path that fits your current health journey.</p>
            </div>
            <div className="grid grid-cols-1 gap-4">
              {[
                { id: 'lose', label: 'Lose Weight', description: 'Burn fat and get leaner', icon: Zap, color: 'text-orange-500', bg: 'bg-orange-50' },
                { id: 'maintain', label: 'Maintain', description: 'Stay healthy and balanced', icon: Target, color: 'text-green-500', bg: 'bg-green-50' },
                { id: 'gain', label: 'Build Muscle', description: 'Gain strength and mass', icon: Weight, color: 'text-blue-500', bg: 'bg-blue-50' }
              ].map((item) => (
                <button
                  key={item.id}
                  onClick={() => {
                    triggerHaptic(hapticPatterns.light);
                    setGoal(item.id as Goal);
                    updateSuggestedCalories(item.id as Goal);
                  }}
                  className={`p-6 rounded-[32px] border-2 transition-all flex items-center gap-5 text-left ios-shadow ${
                    goal === item.id 
                      ? 'border-green-500 bg-green-50/50' 
                      : 'border-white bg-white/50 hover:border-gray-100'
                  }`}
                >
                  <div className={`w-14 h-14 rounded-2xl flex items-center justify-center ${item.bg} ${item.color} shadow-sm`}>
                    <item.icon size={24} strokeWidth={2.5} />
                  </div>
                  <div className="flex-1">
                    <h4 className="text-lg font-black text-gray-900 tracking-tight">{item.label}</h4>
                    <p className="text-sm text-gray-500 font-medium">{item.description}</p>
                    {goal === item.id && (
                      <motion.p 
                        initial={{ opacity: 0, y: 5 }}
                        animate={{ opacity: 1, y: 0 }}
                        className="text-[10px] font-black text-green-600 mt-2 uppercase tracking-widest"
                      >
                        {item.id === 'lose' ? '💡 Focus on whole foods!' : 
                         item.id === 'gain' ? '💡 Prioritize protein intake!' : 
                         '💡 Balance is the key to success!'}
                      </motion.p>
                    )}
                  </div>
                  {goal === item.id && (
                    <div className="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center text-white shadow-lg">
                      <Check size={16} strokeWidth={3} />
                    </div>
                  )}
                </button>
              ))}
            </div>
          </motion.div>
        );
      case 4:
        return (
          <motion.div 
            key="step4"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-8"
          >
            <div className="space-y-2">
              <h2 className="text-3xl font-black text-gray-900 tracking-tight">Daily Calorie Target</h2>
              <p className="text-gray-500 font-medium">Based on your goal, we suggest this daily limit.</p>
            </div>
            <div className="glass-card p-10 rounded-[48px] text-center space-y-6 ios-shadow border-white/50">
              <div className="space-y-2">
                <p className="text-[10px] font-black uppercase tracking-[0.2em] text-gray-400">Suggested Limit</p>
                <div className="flex items-center justify-center gap-4">
                  <input 
                    type="number" 
                    value={calorieLimit}
                    onChange={(e) => {
                      const val = parseInt(e.target.value);
                      setCalorieLimit(val);
                      updateSuggestedMacros(goal, val);
                    }}
                    className="w-40 bg-transparent text-6xl font-black text-gray-900 text-center focus:outline-none tracking-tighter"
                  />
                  <span className="text-2xl font-black text-gray-300">kcal</span>
                </div>
              </div>
              <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                <motion.div 
                  initial={{ width: 0 }}
                  animate={{ width: '100%' }}
                  className="h-full bg-green-500"
                />
              </div>
              <p className="text-xs text-gray-400 font-bold leading-relaxed">
                You can always adjust this later in your settings. This is just a starting point for your journey.
              </p>
            </div>
          </motion.div>
        );
      case 5:
        return (
          <motion.div 
            key="step5"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-8"
          >
            <div className="space-y-2">
              <h2 className="text-3xl font-black text-gray-900 tracking-tight">Macronutrient Goals</h2>
              <p className="text-gray-500 font-medium">We've calculated these based on your calorie target.</p>
            </div>
            <div className="grid grid-cols-1 gap-4">
              {[
                { label: 'Protein', value: proteinGoal, setter: setProteinGoal, color: 'text-blue-500', bg: 'bg-blue-50' },
                { label: 'Carbs', value: carbsGoal, setter: setCarbsGoal, color: 'text-orange-500', bg: 'bg-orange-50' },
                { label: 'Fats', value: fatsGoal, setter: setFatsGoal, color: 'text-purple-500', bg: 'bg-purple-50' }
              ].map((item) => (
                <div key={item.label} className="glass-card p-6 rounded-[32px] flex items-center justify-between ios-shadow border-white/50">
                  <div className="flex items-center gap-4">
                    <div className={`w-12 h-12 rounded-2xl flex items-center justify-center ${item.bg} ${item.color}`}>
                      <Zap size={20} strokeWidth={2.5} />
                    </div>
                    <span className="text-lg font-black text-gray-900 tracking-tight">{item.label}</span>
                  </div>
                  <div className="flex items-center gap-3">
                    <input 
                      type="number" 
                      value={item.value}
                      onChange={(e) => item.setter(parseInt(e.target.value))}
                      className="w-20 bg-transparent text-2xl font-black text-gray-900 text-right focus:outline-none"
                    />
                    <span className="text-sm font-bold text-gray-300">g</span>
                  </div>
                </div>
              ))}
            </div>
          </motion.div>
        );
      default:
        return null;
    }
  };

  return (
    <div className="flex flex-col min-h-screen bg-[#F7F8FA] p-8">
      {/* Progress Bar */}
      <div className="flex gap-2 mb-12">
        {Array.from({ length: totalSteps }).map((_, i) => (
          <div 
            key={i} 
            className={`h-1.5 flex-1 rounded-full transition-all duration-500 ${
              i + 1 <= step ? 'bg-green-500' : 'bg-gray-200'
            }`}
          />
        ))}
      </div>

      <div className="flex-1">
        <AnimatePresence mode="wait">
          {renderStep()}
        </AnimatePresence>
      </div>

      {/* Navigation */}
      <div className="flex gap-4 mt-12">
        {step > 1 && (
          <button 
            onClick={handleBack}
            className="w-20 h-20 glass rounded-[32px] flex items-center justify-center text-gray-400 hover:text-gray-900 transition-all ios-shadow active:scale-90"
          >
            <ChevronLeft size={24} strokeWidth={2.5} />
          </button>
        )}
        <button 
          onClick={handleNext}
          disabled={isSaving}
          className="flex-1 bg-gray-900 text-white rounded-[32px] font-black text-lg flex items-center justify-center gap-3 shadow-2xl hover:bg-black transition-all active:scale-[0.98] ios-shadow disabled:opacity-50"
        >
          {isSaving ? (
            <Loader2 className="animate-spin" size={24} />
          ) : (
            <>
              {step === totalSteps ? 'Complete Profile' : 'Continue'}
              <ChevronRight size={24} strokeWidth={2.5} />
            </>
          )}
        </button>
      </div>
    </div>
  );
};

export default OnboardingScreen;
