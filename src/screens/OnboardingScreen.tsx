import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion, AnimatePresence } from 'motion/react';
import { 
  ChevronRight, 
  ChevronLeft, 
  Sparkles, 
  User, 
  Ruler, 
  Weight, 
  Target, 
  Utensils, 
  GraduationCap, 
  Activity, 
  ShieldCheck, 
  Camera, 
  Bell, 
  Flame, 
  Check, 
  Loader2 
} from 'lucide-react';
import { useUser } from '../contexts/UserContext';
import { saveUserProfile } from '../services/storageService';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { Goal, Gender, Lifestyle, ActivityLevel } from '../types';

const OnboardingScreen: React.FC = () => {
  const navigate = useNavigate();
  const { profile, refreshProfile } = useUser();
  const [step, setStep] = useState(1);
  const [isSaving, setIsSaving] = useState(false);

  // Step 2: Personal Info
  const [name, setName] = useState(profile?.displayName || 'Champion');
  const [dob, setDob] = useState(profile?.dob || '2002-05-15');
  const [gender, setGender] = useState<Gender>(profile?.gender || 'male');

  // Step 3: Body Metrics
  const [isImperial, setIsImperial] = useState(false);
  const [heightCm, setHeightCm] = useState(profile?.height || 175);
  const [weightKg, setWeightKg] = useState(profile?.weight || 70);

  // Step 4: Fitness Goal
  const [goal, setGoal] = useState<Goal>(profile?.goal || 'maintain');

  // Step 5: Dietary Preferences
  const [dietaryPrefs, setDietaryPrefs] = useState<string[]>(
    profile?.dietaryPreferences || ['Vegetarian']
  );
  const [allergiesText, setAllergiesText] = useState(
    profile?.allergies?.join(', ') || ''
  );

  // Step 6: Lifestyle & MessOS
  const [lifestyle, setLifestyle] = useState<Lifestyle>(profile?.lifestyle || 'student');
  const [isHostelUser, setIsHostelUser] = useState(profile?.isHostelUser ?? true);
  const [budgetRange, setBudgetRange] = useState(profile?.budgetRange || 'moderate');

  // Step 7: Activity Level & TDEE
  const [activityLevel, setActivityLevel] = useState<ActivityLevel>(
    profile?.activityLevel || 'moderate'
  );

  // Step 8: Permissions & Confirmation
  const [permCamera, setPermCamera] = useState(true);
  const [permSteps, setPermSteps] = useState(true);
  const [permNotify, setPermNotify] = useState(true);

  const totalSteps = 8;

  // Auto-calculated fields
  const calculateAge = (dobString: string): number => {
    const birthday = new Date(dobString);
    const ageDifMs = Date.now() - birthday.getTime();
    const ageDate = new Date(ageDifMs);
    return Math.abs(ageDate.getUTCFullYear() - 1970) || 22;
  };
  const age = calculateAge(dob);

  const heightM = heightCm / 100;
  const liveBmi = parseFloat((weightKg / (heightM * heightM)).toFixed(1));

  // TDEE and calorie limit auto-calculation
  const calculateTargets = () => {
    // Mifflin-St Jeor formula
    const s = gender === 'female' ? -161 : 5;
    const bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * age) + s;
    
    const multipliers: Record<ActivityLevel, number> = {
      sedentary: 1.2,
      lightly_active: 1.375,
      moderate: 1.55,
      very_active: 1.725,
    };
    const tdee = Math.round(bmr * (multipliers[activityLevel] || 1.55));
    
    let targetCalories = tdee;
    if (goal === 'lose') targetCalories = tdee - 450;
    if (goal === 'gain') targetCalories = tdee + 400;
    if (goal === 'endurance') targetCalories = tdee + 200;

    targetCalories = Math.max(1300, Math.min(4200, targetCalories));

    // Balanced Macros
    const proteinG = Math.round((targetCalories * 0.30) / 4);
    const carbsG = Math.round((targetCalories * 0.45) / 4);
    const fatsG = Math.round((targetCalories * 0.25) / 9);

    return { targetCalories, proteinG, carbsG, fatsG, tdee };
  };

  const { targetCalories, proteinG, carbsG, fatsG } = calculateTargets();

  const toggleDietPref = (pref: string) => {
    if (dietaryPrefs.includes(pref)) {
      setDietaryPrefs(dietaryPrefs.filter(p => p !== pref));
    } else {
      setDietaryPrefs([...dietaryPrefs, pref]);
    }
  };

  const handleNext = () => {
    triggerHaptic(hapticPatterns.light);
    if (step < totalSteps) {
      setStep(step + 1);
    } else {
      handleComplete();
    }
  };

  const handleBack = () => {
    triggerHaptic(hapticPatterns.light);
    if (step > 1) {
      setStep(step - 1);
    }
  };

  const handleComplete = async () => {
    setIsSaving(true);
    triggerHaptic(hapticPatterns.medium);

    try {
      const allergiesList = allergiesText
        .split(',')
        .map(a => a.trim())
        .filter(Boolean);

      await saveUserProfile({
        displayName: name,
        dob,
        age,
        gender,
        height: heightCm,
        weight: weightKg,
        bmi: liveBmi,
        goal,
        dietaryPreferences: dietaryPrefs,
        allergies: allergiesList,
        lifestyle,
        isHostelUser,
        budgetRange,
        activityLevel,
        calorieLimit: targetCalories,
        proteinGoal: proteinG,
        carbsGoal: carbsG,
        fatsGoal: fatsG,
        waterGoal: weightKg * 35, // ~35ml per kg bodyweight
        hasCompletedOnboarding: true,
      });

      await refreshProfile();
      triggerHaptic(hapticPatterns.success);
      navigate('/');
    } catch (e) {
      console.error('Failed to complete onboarding:', e);
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col justify-between max-w-md mx-auto relative overflow-hidden text-gray-800">
      {/* Top Header with Progress Dots */}
      <div className="pt-8 px-6 pb-2">
        <div className="flex items-center justify-between mb-4">
          {step > 1 ? (
            <button
              onClick={handleBack}
              className="w-10 h-10 rounded-2xl glass flex items-center justify-center text-gray-600 border border-gray-100 hover:bg-white transition-colors"
            >
              <ChevronLeft size={20} />
            </button>
          ) : (
            <div className="w-10 h-10" />
          )}

          <div className="flex gap-1.5 items-center">
            {Array.from({ length: totalSteps }).map((_, i) => (
              <motion.div
                key={i}
                animate={{
                  width: step === i + 1 ? 22 : 6,
                  backgroundColor: step === i + 1 ? '#059669' : '#e2e8f0',
                }}
                className="h-2 rounded-full transition-all"
              />
            ))}
          </div>

          <span className="text-xs font-bold text-emerald-700 bg-emerald-50 px-2.5 py-1 rounded-full border border-emerald-100">
            {step}/{totalSteps}
          </span>
        </div>
      </div>

      {/* Main Form Content Step-by-Step */}
      <div className="flex-1 px-6 py-2 flex flex-col justify-center overflow-y-auto">
        <AnimatePresence mode="wait">
          {/* STEP 1: Welcome Splash */}
          {step === 1 && (
            <motion.div
              key="step1"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              className="text-center space-y-6 py-6"
            >
              <div className="w-24 h-24 bg-gradient-to-br from-emerald-500 to-teal-600 rounded-[32px] mx-auto flex items-center justify-center text-white shadow-2xl shadow-emerald-500/30">
                <Sparkles size={44} />
              </div>
              <div className="space-y-2">
                <h1 className="text-3xl font-black text-gray-900 tracking-tight">
                  NutriSnap AI v2.0
                </h1>
                <p className="text-sm font-semibold text-emerald-600 tracking-wide uppercase">
                  Local-First • 100% Private Health
                </p>
                <p className="text-sm text-gray-500 max-w-xs mx-auto leading-relaxed pt-2">
                  Snap meals, track calories, monitor body composition, and master campus dining — completely on your device.
                </p>
              </div>

              <div className="p-4 glass rounded-2xl border border-emerald-100 text-left space-y-2 max-w-sm mx-auto">
                <div className="flex items-center gap-2.5 text-xs font-bold text-gray-700">
                  <ShieldCheck size={16} className="text-emerald-600 shrink-0" />
                  <span>Zero Cloud Database Tracking</span>
                </div>
                <div className="flex items-center gap-2.5 text-xs font-bold text-gray-700">
                  <Activity size={16} className="text-teal-600 shrink-0" />
                  <span>On-Device Gemini Multimodal AI</span>
                </div>
              </div>
            </motion.div>
          )}

          {/* STEP 2: Personal Info */}
          {step === 2 && (
            <motion.div
              key="step2"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              className="space-y-6"
            >
              <div>
                <h2 className="text-2xl font-black text-gray-900">About You</h2>
                <p className="text-xs text-gray-500 mt-1">
                  We customize your metabolic formula based on biological age and sex.
                </p>
              </div>

              <div className="space-y-4">
                <div>
                  <label className="text-xs font-bold text-gray-600 uppercase tracking-wider block mb-1.5">
                    Your Name
                  </label>
                  <input
                    type="text"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="Enter your name"
                    className="w-full px-4 py-3.5 rounded-2xl bg-white border border-gray-200 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 text-sm font-medium"
                  />
                </div>

                <div>
                  <div className="flex justify-between items-center mb-1.5">
                    <label className="text-xs font-bold text-gray-600 uppercase tracking-wider">
                      Date of Birth
                    </label>
                    <span className="text-xs font-bold text-emerald-600">{age} years old</span>
                  </div>
                  <input
                    type="date"
                    value={dob}
                    onChange={(e) => setDob(e.target.value)}
                    className="w-full px-4 py-3.5 rounded-2xl bg-white border border-gray-200 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 text-sm font-medium"
                  />
                </div>

                <div>
                  <label className="text-xs font-bold text-gray-600 uppercase tracking-wider block mb-1.5">
                    Biological Sex
                  </label>
                  <div className="grid grid-cols-2 gap-2.5">
                    {(['male', 'female'] as Gender[]).map((g) => (
                      <button
                        key={g}
                        type="button"
                        onClick={() => setGender(g)}
                        className={`py-3.5 px-4 rounded-2xl text-xs font-bold capitalize border transition-all ${
                          gender === g
                            ? 'bg-emerald-600 text-white border-emerald-600 shadow-md shadow-emerald-600/20'
                            : 'bg-white text-gray-700 border-gray-200 hover:border-gray-300'
                        }`}
                      >
                        {g}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            </motion.div>
          )}

          {/* STEP 3: Body Metrics */}
          {step === 3 && (
            <motion.div
              key="step3"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              className="space-y-6"
            >
              <div className="flex justify-between items-start">
                <div>
                  <h2 className="text-2xl font-black text-gray-900">Body Metrics</h2>
                  <p className="text-xs text-gray-500 mt-1">Live BMI & baseline anthropometry.</p>
                </div>
                <button
                  type="button"
                  onClick={() => setIsImperial(!isImperial)}
                  className="px-3 py-1.5 rounded-full text-xs font-bold bg-gray-100 text-gray-600 border border-gray-200"
                >
                  {isImperial ? 'Metric (cm/kg)' : 'Imperial (ft/lbs)'}
                </button>
              </div>

              {/* Live BMI Pill */}
              <div className="p-4 rounded-2xl bg-emerald-50/70 border border-emerald-200 flex items-center justify-between">
                <div>
                  <span className="text-[10px] font-bold uppercase tracking-wider text-emerald-800">
                    Calculated BMI
                  </span>
                  <div className="text-2xl font-black text-emerald-950">{liveBmi}</div>
                </div>
                <span className="text-xs font-bold px-3 py-1 bg-white rounded-full text-emerald-700 shadow-sm border border-emerald-100">
                  {liveBmi < 18.5 ? 'Underweight' : liveBmi < 25 ? 'Normal BMI' : liveBmi < 30 ? 'Overweight' : 'Obese'}
                </span>
              </div>

              <div className="space-y-4">
                <div>
                  <div className="flex justify-between items-center mb-1.5">
                    <label className="text-xs font-bold text-gray-600 uppercase tracking-wider">
                      Height
                    </label>
                    <span className="text-xs font-bold text-gray-900">
                      {isImperial ? `${Math.floor(heightCm / 30.48)}' ${Math.round((heightCm % 30.48) / 2.54)}"` : `${heightCm} cm`}
                    </span>
                  </div>
                  <input
                    type="range"
                    min={120}
                    max={230}
                    value={heightCm}
                    onChange={(e) => setHeightCm(Number(e.target.value))}
                    className="w-full accent-emerald-600 cursor-pointer"
                  />
                </div>

                <div>
                  <div className="flex justify-between items-center mb-1.5">
                    <label className="text-xs font-bold text-gray-600 uppercase tracking-wider">
                      Weight
                    </label>
                    <span className="text-xs font-bold text-gray-900">
                      {isImperial ? `${Math.round(weightKg * 2.20462)} lbs` : `${weightKg} kg`}
                    </span>
                  </div>
                  <input
                    type="range"
                    min={35}
                    max={180}
                    value={weightKg}
                    onChange={(e) => setWeightKg(Number(e.target.value))}
                    className="w-full accent-emerald-600 cursor-pointer"
                  />
                </div>
              </div>
            </motion.div>
          )}

          {/* STEP 4: Fitness Goal */}
          {step === 4 && (
            <motion.div
              key="step4"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              className="space-y-6"
            >
              <div>
                <h2 className="text-2xl font-black text-gray-900">Your Main Goal</h2>
                <p className="text-xs text-gray-500 mt-1">Calorie limit & macros will adapt automatically.</p>
              </div>

              <div className="grid grid-cols-1 gap-3">
                {[
                  { id: 'lose', title: 'Lose Weight & Fat', desc: 'Caloric deficit with high protein for satiety', icon: '🔥' },
                  { id: 'maintain', title: 'Maintain & Tone', desc: 'Sustained energy and body recomposition', icon: '⚖️' },
                  { id: 'gain', title: 'Build Muscle Mass', desc: 'Clean surplus tailored for progressive overload', icon: '💪' },
                  { id: 'endurance', title: 'Boost Athletic Stamina', desc: 'Optimal complex carb and recovery fueling', icon: '⚡' },
                ].map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => setGoal(item.id as Goal)}
                    className={`p-4 rounded-2xl text-left border flex items-center gap-4 transition-all ${
                      goal === item.id
                        ? 'bg-emerald-50/80 border-emerald-500 ring-2 ring-emerald-500/20 shadow-sm'
                        : 'bg-white border-gray-200 hover:border-gray-300'
                    }`}
                  >
                    <div className="text-2xl">{item.icon}</div>
                    <div className="flex-1">
                      <h4 className="text-sm font-bold text-gray-900">{item.title}</h4>
                      <p className="text-xs text-gray-500">{item.desc}</p>
                    </div>
                    {goal === item.id && <Check size={18} className="text-emerald-600" />}
                  </button>
                ))}
              </div>
            </motion.div>
          )}

          {/* STEP 5: Dietary Preferences */}
          {step === 5 && (
            <motion.div
              key="step5"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              className="space-y-6"
            >
              <div>
                <h2 className="text-2xl font-black text-gray-900">Dietary Style</h2>
                <p className="text-xs text-gray-500 mt-1">Personalizes AI meal suggestions and mess swaps.</p>
              </div>

              <div className="flex flex-wrap gap-2">
                {[
                  'Vegetarian',
                  'Vegan',
                  'Eggetarian',
                  'Non-Vegetarian',
                  'Jain (No Root Veg)',
                  'Gluten-Free',
                  'Keto',
                  'Diabetic-Friendly',
                  'High-Protein',
                ].map((pref) => {
                  const active = dietaryPrefs.includes(pref);
                  return (
                    <button
                      key={pref}
                      type="button"
                      onClick={() => toggleDietPref(pref)}
                      className={`px-4 py-2.5 rounded-full text-xs font-bold border transition-all ${
                        active
                          ? 'bg-emerald-600 text-white border-emerald-600 shadow-sm'
                          : 'bg-white text-gray-700 border-gray-200 hover:bg-gray-50'
                      }`}
                    >
                      {pref}
                    </button>
                  );
                })}
              </div>

              <div>
                <label className="text-xs font-bold text-gray-600 uppercase tracking-wider block mb-1.5">
                  Food Allergies or Dislikes
                </label>
                <input
                  type="text"
                  placeholder="e.g. Peanuts, Shellfish, Lactose (optional)"
                  value={allergiesText}
                  onChange={(e) => setAllergiesText(e.target.value)}
                  className="w-full px-4 py-3 rounded-2xl bg-white border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500/20"
                />
              </div>
            </motion.div>
          )}

          {/* STEP 6: Lifestyle & MessOS */}
          {step === 6 && (
            <motion.div
              key="step6"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              className="space-y-6"
            >
              <div>
                <h2 className="text-2xl font-black text-gray-900">Daily Lifestyle</h2>
                <p className="text-xs text-gray-500 mt-1">Helps MessOS and meal recommendations.</p>
              </div>

              <div className="space-y-3">
                <label className="text-xs font-bold text-gray-600 uppercase tracking-wider block">
                  Primary Occupation
                </label>
                <div className="grid grid-cols-3 gap-2">
                  {[
                    { id: 'student', label: 'Student' },
                    { id: 'professional', label: 'Professional' },
                    { id: 'athlete', label: 'Athlete' },
                  ].map((item) => (
                    <button
                      key={item.id}
                      type="button"
                      onClick={() => setLifestyle(item.id as Lifestyle)}
                      className={`py-3 px-2 rounded-2xl text-xs font-bold border text-center transition-all ${
                        lifestyle === item.id
                          ? 'bg-emerald-600 text-white border-emerald-600'
                          : 'bg-white text-gray-700 border-gray-200'
                      }`}
                    >
                      {item.label}
                    </button>
                  ))}
                </div>
              </div>

              {/* MessOS Hostel Toggle */}
              <div className="p-4 rounded-2xl bg-emerald-50/70 border border-emerald-200 flex items-center justify-between">
                <div className="pr-3">
                  <h4 className="text-xs font-bold text-emerald-950">Hostel / Campus Mess Diner?</h4>
                  <p className="text-[11px] text-emerald-800/80">
                    Enables MessOS smart meal hacks & campus menus
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => setIsHostelUser(!isHostelUser)}
                  className={`w-12 h-7 rounded-full p-1 transition-colors ${
                    isHostelUser ? 'bg-emerald-600' : 'bg-gray-300'
                  }`}
                >
                  <div
                    className={`w-5 h-5 rounded-full bg-white transition-transform ${
                      isHostelUser ? 'translate-x-5' : 'translate-x-0'
                    }`}
                  />
                </button>
              </div>

              <div>
                <label className="text-xs font-bold text-gray-600 uppercase tracking-wider block mb-1.5">
                  Food Budget Range
                </label>
                <div className="grid grid-cols-3 gap-2">
                  {['Pocket-Friendly', 'Moderate', 'Flexible'].map((b) => (
                    <button
                      key={b}
                      type="button"
                      onClick={() => setBudgetRange(b)}
                      className={`py-2.5 text-xs font-bold rounded-xl border ${
                        budgetRange === b
                          ? 'bg-gray-900 text-white border-gray-900'
                          : 'bg-white text-gray-700 border-gray-200'
                      }`}
                    >
                      {b}
                    </button>
                  ))}
                </div>
              </div>
            </motion.div>
          )}

          {/* STEP 7: Activity Level & Plan */}
          {step === 7 && (
            <motion.div
              key="step7"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              className="space-y-6"
            >
              <div>
                <h2 className="text-2xl font-black text-gray-900">Activity & TDEE</h2>
                <p className="text-xs text-gray-500 mt-1">Calculates your calibrated daily intake.</p>
              </div>

              <div className="grid grid-cols-2 gap-2.5">
                {[
                  { id: 'sedentary', label: 'Sedentary', sub: 'Desk work, <5k steps' },
                  { id: 'lightly_active', label: 'Lightly Active', sub: '1-3 workout sessions' },
                  { id: 'moderate', label: 'Moderate', sub: '3-5 workouts/week' },
                  { id: 'very_active', label: 'Very Active', sub: 'Intense daily training' },
                ].map((act) => (
                  <button
                    key={act.id}
                    type="button"
                    onClick={() => setActivityLevel(act.id as ActivityLevel)}
                    className={`p-3.5 rounded-2xl text-left border transition-all ${
                      activityLevel === act.id
                        ? 'bg-emerald-50 border-emerald-500 ring-2 ring-emerald-500/20'
                        : 'bg-white border-gray-200'
                    }`}
                  >
                    <div className="text-xs font-bold text-gray-900">{act.label}</div>
                    <div className="text-[10px] text-gray-500 mt-0.5">{act.sub}</div>
                  </button>
                ))}
              </div>

              {/* Target Nutrition Card */}
              <div className="p-4 rounded-2xl bg-white border border-gray-200 shadow-sm space-y-3">
                <div className="flex justify-between items-center">
                  <span className="text-xs font-bold text-gray-500 uppercase">Calculated Calorie Target</span>
                  <span className="text-base font-black text-emerald-600">{targetCalories} kcal</span>
                </div>

                <div className="grid grid-cols-3 gap-2 text-center pt-1 border-t border-gray-100">
                  <div className="p-2 rounded-xl bg-blue-50">
                    <span className="text-[10px] font-bold text-blue-700 block">Protein</span>
                    <span className="text-xs font-black text-blue-900">{proteinG}g</span>
                  </div>
                  <div className="p-2 rounded-xl bg-amber-50">
                    <span className="text-[10px] font-bold text-amber-700 block">Carbs</span>
                    <span className="text-xs font-black text-amber-900">{carbsG}g</span>
                  </div>
                  <div className="p-2 rounded-xl bg-rose-50">
                    <span className="text-[10px] font-bold text-rose-700 block">Fats</span>
                    <span className="text-xs font-black text-rose-900">{fatsG}g</span>
                  </div>
                </div>
              </div>
            </motion.div>
          )}

          {/* STEP 8: Permissions & Launch */}
          {step === 8 && (
            <motion.div
              key="step8"
              initial={{ opacity: 0, y: 15 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -15 }}
              className="space-y-6"
            >
              <div>
                <h2 className="text-2xl font-black text-gray-900">Final Step</h2>
                <p className="text-xs text-gray-500 mt-1">Configure your device permissions.</p>
              </div>

              <div className="space-y-3">
                <div className="p-4 rounded-2xl bg-white border border-gray-200 flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="w-9 h-9 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center">
                      <Camera size={18} />
                    </div>
                    <div>
                      <h4 className="text-xs font-bold text-gray-900">Food & Body Camera</h4>
                      <p className="text-[11px] text-gray-500">Scan meals and evaluate body composition</p>
                    </div>
                  </div>
                  <Check size={18} className="text-emerald-600" />
                </div>

                <div className="p-4 rounded-2xl bg-white border border-gray-200 flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="w-9 h-9 rounded-xl bg-teal-100 text-teal-700 flex items-center justify-center">
                      <Activity size={18} />
                    </div>
                    <div>
                      <h4 className="text-xs font-bold text-gray-900">Step & Health Sensor</h4>
                      <p className="text-[11px] text-gray-500">Auto-tracks steps and active burn</p>
                    </div>
                  </div>
                  <Check size={18} className="text-teal-600" />
                </div>

                <div className="p-4 rounded-2xl bg-white border border-gray-200 flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="w-9 h-9 rounded-xl bg-blue-100 text-blue-700 flex items-center justify-center">
                      <Bell size={18} />
                    </div>
                    <div>
                      <h4 className="text-xs font-bold text-gray-900">Smart Hydration Alerts</h4>
                      <p className="text-[11px] text-gray-500">Friendly reminders to stay hydrated</p>
                    </div>
                  </div>
                  <Check size={18} className="text-blue-600" />
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Bottom CTA Button */}
      <div className="p-6 bg-white/70 backdrop-blur-md border-t border-gray-100">
        <button
          onClick={handleNext}
          disabled={isSaving}
          className="w-full py-4 bg-emerald-600 hover:bg-emerald-700 text-white rounded-2xl font-bold shadow-lg shadow-emerald-600/25 flex items-center justify-center gap-2 transition-all"
        >
          {isSaving ? (
            <Loader2 size={20} className="animate-spin" />
          ) : step === totalSteps ? (
            <>
              <span>Get Started Now</span>
              <Check size={18} strokeWidth={2.5} />
            </>
          ) : (
            <>
              <span>Continue</span>
              <ChevronRight size={18} strokeWidth={2.5} />
            </>
          )}
        </button>
      </div>
    </div>
  );
};

export default OnboardingScreen;
