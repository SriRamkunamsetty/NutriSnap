import React, { useState, useEffect, useRef } from 'react';
import { User, Scale, Ruler, Target, Flame, Save, LogOut, ChevronRight, Info, Shield, Bell, Activity, Camera, Loader2, Sparkles, Beef, Wheat, Droplets, Plus, X, Trash2, Bot } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { auth } from '../firebase';
import { saveUserProfile, uploadProfileImage, uploadAIAvatar, clearChatHistory } from '../services/storageService';
import { analyzeBodyImage } from '../services/geminiService';
import { UserProfile, Goal, BodyType, Reminder } from '../types';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { useUser } from '../contexts/UserContext';
import { requestNotificationPermission } from '../lib/notifications';

import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const SettingsScreen: React.FC = () => {
  const { profile, refreshProfile } = useUser();
  const [isEditing, setIsEditing] = useState(false);
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [isUploadingProfile, setIsUploadingProfile] = useState(false);
  const [isUploadingAIAvatar, setIsUploadingAIAvatar] = useState(false);
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [showBMIInfo, setShowBMIInfo] = useState(false);
  const [isClearing, setIsClearing] = useState(false);
  const [isDirty, setIsDirty] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const bodyInputRef = useRef<HTMLInputElement>(null);
  const profileInputRef = useRef<HTMLInputElement>(null);
  const aiAvatarInputRef = useRef<HTMLInputElement>(null);
  
  const [formData, setFormData] = useState({
    height: 175,
    weight: 70,
    goal: 'maintain' as Goal,
    calorieLimit: 2000,
    proteinGoal: 150,
    carbsGoal: 200,
    fatsGoal: 70,
    proteinPct: 30,
    carbsPct: 40,
    fatsPct: 30,
    displayName: auth.currentUser?.displayName || 'User',
    photoURL: auth.currentUser?.photoURL || '',
    aiAvatarURL: '',
    bmi: 22.9,
    bodyType: 'unknown' as BodyType,
    fatEstimate: 0,
    waterGoal: 2500,
    reminders: [] as Reminder[]
  });

  const [initialData, setInitialData] = useState(formData);

  useEffect(() => {
    if (profile) {
      const calorieLimit = profile.calorieLimit || 2000;
      const proteinGoal = profile.proteinGoal || 150;
      const carbsGoal = profile.carbsGoal || 200;
      const fatsGoal = profile.fatsGoal || 70;

      // Calculate initial percentages based on grams
      const pPct = Math.round((proteinGoal * 4 / calorieLimit) * 100);
      const cPct = Math.round((carbsGoal * 4 / calorieLimit) * 100);
      const fPct = 100 - pPct - cPct;

      const data = {
        height: profile.height || 175,
        weight: profile.weight || 70,
        goal: profile.goal || 'maintain',
        calorieLimit,
        proteinGoal,
        carbsGoal,
        fatsGoal,
        proteinPct: pPct,
        carbsPct: cPct,
        fatsPct: fPct,
        displayName: profile.displayName || auth.currentUser?.displayName || 'User',
        photoURL: profile.photoURL || auth.currentUser?.photoURL || '',
        aiAvatarURL: profile.aiAvatarURL || '',
        bmi: profile.bmi || 22.9,
        bodyType: profile.bodyType || 'unknown',
        fatEstimate: profile.fatEstimate || 0,
        waterGoal: profile.waterGoal || 2500,
        reminders: profile.reminders || []
      };
      setFormData(data);
      setInitialData(data);
    }
  }, [profile]);

  useEffect(() => {
    const hasChanges = JSON.stringify(formData) !== JSON.stringify(initialData);
    setIsDirty(hasChanges);
  }, [formData, initialData]);

  const calculateBMI = (h: number, w: number) => {
    if (!h || !w) return 0;
    return Math.round((w / Math.pow(h / 100, 2)) * 10) / 10;
  };

  const bmi = calculateBMI(formData.height, formData.weight);
  
  const getBMIDetails = (bmiValue: number) => {
    if (bmiValue < 18.5) return { label: 'Underweight', color: 'text-blue-500', bg: 'bg-blue-50/50', border: 'border-blue-100', barColor: 'bg-blue-500' };
    if (bmiValue < 25) return { label: 'Healthy', color: 'text-green-600', bg: 'bg-green-50/50', border: 'border-green-100', barColor: 'bg-green-500' };
    if (bmiValue < 30) return { label: 'Overweight', color: 'text-orange-500', bg: 'bg-orange-50/50', border: 'border-orange-100', barColor: 'bg-orange-500' };
    return { label: 'Obese', color: 'text-red-500', bg: 'bg-red-50/50', border: 'border-red-100', barColor: 'bg-red-500' };
  };

  const bmiDetails = getBMIDetails(bmi);

  const validate = () => {
    const newErrors: Record<string, string> = {};
    
    if (formData.height < 50 || formData.height > 250) {
      newErrors.height = 'Height must be between 50 and 250 cm';
    }
    
    if (formData.weight < 20 || formData.weight > 300) {
      newErrors.weight = 'Weight must be between 20 and 300 kg';
    }
    
    if (formData.calorieLimit < 1000 || formData.calorieLimit > 5000) {
      newErrors.calorieLimit = 'Calories must be between 1000 and 5000 kcal';
    }
    
    if (formData.waterGoal < 500 || formData.waterGoal > 10000) {
      newErrors.waterGoal = 'Water goal must be between 500 and 10000 ml';
    }

    if (formData.proteinGoal < 0 || formData.proteinGoal > 500) {
      newErrors.proteinGoal = 'Protein must be between 0 and 500 g';
    }

    if (formData.carbsGoal < 0 || formData.carbsGoal > 1000) {
      newErrors.carbsGoal = 'Carbs must be between 0 and 1000 g';
    }

    if (formData.fatsGoal < 0 || formData.fatsGoal > 300) {
      newErrors.fatsGoal = 'Fats must be between 0 and 300 g';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSave = async () => {
    if (!validate()) {
      triggerHaptic(hapticPatterns.error);
      return;
    }
    triggerHaptic(hapticPatterns.medium);
    try {
      await saveUserProfile({
        ...formData,
        bmi
      });
      setIsEditing(false);
      await refreshProfile();
      triggerHaptic(hapticPatterns.success);
    } catch (error) {
      triggerHaptic(hapticPatterns.error);
      console.error("Save failed", error);
    }
  };

  const handleInputChange = (field: string, value: any) => {
    setFormData(prev => {
      const newData = { ...prev, [field]: value };
      
      // If calorie limit or percentages change, update grams
      if (['calorieLimit', 'proteinPct', 'carbsPct', 'fatsPct'].includes(field)) {
        const calories = newData.calorieLimit;
        newData.proteinGoal = Math.round((calories * newData.proteinPct / 100) / 4);
        newData.carbsGoal = Math.round((calories * newData.carbsPct / 100) / 4);
        newData.fatsGoal = Math.round((calories * newData.fatsPct / 100) / 9);
      }
      
      return newData;
    });
  };

  const addReminder = async () => {
    triggerHaptic(hapticPatterns.light);
    const hasPermission = await requestNotificationPermission();
    if (!hasPermission) {
      alert("Please enable notifications to use reminders.");
      return;
    }

    const newReminder: Reminder = {
      id: Math.random().toString(36).substr(2, 9),
      time: '08:00',
      type: 'meal',
      enabled: true
    };
    setFormData(prev => ({
      ...prev,
      reminders: [...prev.reminders, newReminder]
    }));
    setIsEditing(true);
  };

  const updateReminder = (id: string, updates: Partial<Reminder>) => {
    setFormData(prev => ({
      ...prev,
      reminders: prev.reminders.map(r => r.id === id ? { ...r, ...updates } : r)
    }));
  };

  const toggleReminder = (id: string) => {
    triggerHaptic(hapticPatterns.light);
    setFormData(prev => ({
      ...prev,
      reminders: prev.reminders.map(r => r.id === id ? { ...r, enabled: !r.enabled } : r)
    }));
  };

  const removeReminder = (id: string) => {
    triggerHaptic(hapticPatterns.light);
    setFormData(prev => ({
      ...prev,
      reminders: prev.reminders.filter(r => r.id !== id)
    }));
  };

  const handleBodyImageChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsAnalyzing(true);
    triggerHaptic(hapticPatterns.medium);
    
    try {
      const reader = new FileReader();
      reader.onloadend = async () => {
        const base64 = (reader.result as string).split(',')[1];
        const result = await analyzeBodyImage(base64, file.type);
        
        setFormData(prev => ({
          ...prev,
          bodyType: result.bodyType as BodyType,
          fatEstimate: result.fatEstimate
        }));
        setIsEditing(true);
        setIsAnalyzing(false);
        triggerHaptic(hapticPatterns.success);
      };
      reader.readAsDataURL(file);
    } catch (error) {
      console.error("Body analysis failed", error);
      setIsAnalyzing(false);
      triggerHaptic(hapticPatterns.error);
    }
  };

  const handleProfileImageChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsUploadingProfile(true);
    triggerHaptic(hapticPatterns.medium);
    
    try {
      const url = await uploadProfileImage(file);
      setFormData(prev => ({ ...prev, photoURL: url }));
      await refreshProfile();
      setIsUploadingProfile(false);
      triggerHaptic(hapticPatterns.success);
    } catch (error) {
      console.error("Profile upload failed", error);
      setIsUploadingProfile(false);
      triggerHaptic(hapticPatterns.error);
    }
  };

  const handleAIAvatarChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsUploadingAIAvatar(true);
    triggerHaptic(hapticPatterns.medium);
    
    try {
      const url = await uploadAIAvatar(file);
      setFormData(prev => ({ ...prev, aiAvatarURL: url }));
      await refreshProfile();
      setIsUploadingAIAvatar(false);
      triggerHaptic(hapticPatterns.success);
    } catch (error) {
      console.error("AI Avatar upload failed", error);
      setIsUploadingAIAvatar(false);
      triggerHaptic(hapticPatterns.error);
    }
  };

  const handleClearChat = async () => {
    setIsClearing(true);
    triggerHaptic(hapticPatterns.medium);
    try {
      await clearChatHistory();
      setShowClearConfirm(false);
      triggerHaptic(hapticPatterns.success);
    } catch (error) {
      console.error("Clear chat failed", error);
      triggerHaptic(hapticPatterns.error);
    } finally {
      setIsClearing(false);
    }
  };

  const handleSignOut = async () => {
    triggerHaptic(hapticPatterns.medium);
    try {
      await auth.signOut();
    } catch (error) {
      console.error("Sign out failed", error);
    }
  };

  return (
    <div className="space-y-10 pb-10">
      {/* Profile Header */}
      <div className="flex flex-col items-center text-center space-y-4 pt-4">
        <div className="flex gap-8 items-end">
          {/* User Avatar */}
          <div className="flex flex-col items-center gap-2">
            <div className="relative group">
              <button 
                onClick={() => profileInputRef.current?.click()}
                disabled={isUploadingProfile}
                className="w-24 h-24 bg-green-500 rounded-[32px] flex items-center justify-center text-white text-3xl font-bold shadow-2xl shadow-green-500/30 ios-shadow group-hover:scale-105 transition-transform overflow-hidden relative"
              >
                {formData.photoURL ? (
                  <img 
                    src={formData.photoURL} 
                    alt="Profile" 
                    className="w-full h-full object-cover"
                    referrerPolicy="no-referrer"
                  />
                ) : (
                  formData.displayName.charAt(0)
                )}
                
                {isUploadingProfile && (
                  <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
                    <Loader2 size={24} className="animate-spin text-white" />
                  </div>
                )}
                
                <div className="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors flex items-center justify-center opacity-0 group-hover:opacity-100">
                  <Camera size={20} className="text-white" />
                </div>
              </button>
              <input 
                type="file" 
                ref={profileInputRef} 
                onChange={handleProfileImageChange} 
                accept="image/*" 
                className="hidden" 
              />
              <div className="absolute -bottom-1 -right-1 w-8 h-8 glass rounded-xl flex items-center justify-center text-green-600 ios-shadow pointer-events-none">
                <User size={16} strokeWidth={2.5} />
              </div>
            </div>
            <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">Your Avatar</span>
          </div>

          {/* AI Avatar */}
          <div className="flex flex-col items-center gap-2">
            <div className="relative group">
              <button 
                onClick={() => aiAvatarInputRef.current?.click()}
                disabled={isUploadingAIAvatar}
                className="w-24 h-24 bg-purple-500 rounded-[32px] flex items-center justify-center text-white text-3xl font-bold shadow-2xl shadow-purple-500/30 ios-shadow group-hover:scale-105 transition-transform overflow-hidden relative"
              >
                {formData.aiAvatarURL ? (
                  <img 
                    src={formData.aiAvatarURL} 
                    alt="AI Avatar" 
                    className="w-full h-full object-cover"
                    referrerPolicy="no-referrer"
                  />
                ) : (
                  <Bot size={40} />
                )}
                
                {isUploadingAIAvatar && (
                  <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
                    <Loader2 size={24} className="animate-spin text-white" />
                  </div>
                )}
                
                <div className="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors flex items-center justify-center opacity-0 group-hover:opacity-100">
                  <Camera size={20} className="text-white" />
                </div>
              </button>
              <input 
                type="file" 
                ref={aiAvatarInputRef} 
                onChange={handleAIAvatarChange} 
                accept="image/*" 
                className="hidden" 
              />
              <div className="absolute -bottom-1 -right-1 w-8 h-8 glass rounded-xl flex items-center justify-center text-purple-600 ios-shadow pointer-events-none">
                <Sparkles size={16} strokeWidth={2.5} />
              </div>
            </div>
            <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">AI Coach Avatar</span>
          </div>
        </div>
        <div className="space-y-1">
          <p className="text-sm text-gray-400 font-medium tracking-tight">{auth.currentUser?.email}</p>
        </div>
        {!isEditing && (
          <motion.button 
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            onClick={() => {
              triggerHaptic(hapticPatterns.light);
              setIsEditing(true);
            }}
            className="px-8 py-3 bg-white border border-gray-100 rounded-2xl text-sm font-bold text-green-600 hover:bg-green-50 transition-all ios-shadow ios-tap flex items-center gap-2"
          >
            <User size={16} strokeWidth={2.5} />
            Edit Profile
          </motion.button>
        )}
      </div>

      {/* Health Metrics Card */}
      <div className="glass-card p-8 rounded-[40px] space-y-6 ios-shadow relative overflow-hidden">
        <div className="absolute top-0 right-0 p-6 opacity-[0.03] pointer-events-none">
          <Activity size={120} className="text-green-600" />
        </div>

        <div className="flex items-center justify-between relative z-10">
          <div className="flex items-center gap-2">
            <div className="w-2.5 h-2.5 bg-green-500 rounded-full animate-pulse shadow-[0_0_10px_rgba(34,197,94,0.5)]" />
            <h3 className="text-xs font-bold text-gray-400 uppercase tracking-widest">Health Index</h3>
          </div>
          <div className="flex items-center gap-2">
            <motion.span 
              key={bmiDetails.label}
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              className={cn(
                "text-[10px] font-black px-3 py-1 rounded-full border uppercase tracking-widest transition-all shadow-sm",
                bmiDetails.color, bmiDetails.bg, bmiDetails.border
              )}
            >
              {bmiDetails.label}
            </motion.span>
            <button 
              onClick={() => setShowBMIInfo(true)}
              className="w-8 h-8 glass rounded-full flex items-center justify-center text-gray-400 hover:text-green-600 transition-all ios-tap border border-white/50 shadow-sm"
            >
              <Info size={16} />
            </button>
          </div>
        </div>
        
        <div className="flex items-center gap-4 relative z-10">
          <div className="flex items-baseline gap-2">
            <motion.span 
              key={bmi}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              className="text-7xl font-black text-gray-900 tracking-tighter"
            >
              {bmi}
            </motion.span>
            <span className="text-gray-400 font-bold text-sm tracking-tight">BMI</span>
          </div>
        </div>
        
        <div className="space-y-4 relative z-10">
          <div className="h-4 bg-gray-100/50 rounded-full overflow-hidden border border-white/20 relative shadow-inner">
            {/* Scale Markers */}
            <div className="absolute inset-0 flex">
              <div className="h-full border-r border-white/40" style={{ width: '46.25%' }} /> {/* 18.5 mark */}
              <div className="h-full border-r border-white/40" style={{ width: '16.25%' }} /> {/* 25 mark */}
              <div className="h-full border-r border-white/40" style={{ width: '12.5%' }} />  {/* 30 mark */}
            </div>
            
            <motion.div 
              initial={{ width: 0 }}
              animate={{ width: `${Math.min((bmi / 40) * 100, 100) || 0}%` }}
              className={cn(
                "h-full rounded-full transition-all duration-1000 shadow-[0_0_15px_rgba(0,0,0,0.1)]",
                bmiDetails.barColor
              )}
            >
              <div className="w-full h-full bg-gradient-to-r from-white/20 to-transparent" />
            </motion.div>
          </div>
          
          <div className="flex justify-between px-1">
            <div className="text-center">
              <p className="text-[8px] font-black text-gray-300 uppercase tracking-tighter">Under</p>
              <p className="text-[10px] font-bold text-gray-400">18.5</p>
            </div>
            <div className="text-center">
              <p className="text-[8px] font-black text-gray-300 uppercase tracking-tighter">Healthy</p>
              <p className="text-[10px] font-bold text-gray-400">25.0</p>
            </div>
            <div className="text-center">
              <p className="text-[8px] font-black text-gray-300 uppercase tracking-tighter">Over</p>
              <p className="text-[10px] font-bold text-gray-400">30.0</p>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4 pt-2 relative z-10">
          <div className="glass p-4 rounded-2xl text-center ios-shadow border border-white/50">
            <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest mb-1">Body Type</p>
            <p className="font-bold text-gray-900 capitalize text-lg tracking-tight">
              {formData.bodyType === 'unknown' ? 'Not Scanned' : formData.bodyType}
            </p>
          </div>
          <div className="glass p-4 rounded-2xl text-center ios-shadow border border-white/50">
            <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest mb-1">Fat Estimate</p>
            <p className="font-bold text-gray-900 text-lg tracking-tight">
              {formData.fatEstimate > 0 ? `${formData.fatEstimate}%` : '--'}
            </p>
          </div>
        </div>

        <button 
          onClick={() => bodyInputRef.current?.click()}
          disabled={isAnalyzing}
          className="w-full py-5 glass hover:bg-white/60 rounded-[24px] text-sm font-bold transition-all flex items-center justify-center gap-3 border border-white/50 ios-shadow group"
        >
          {isAnalyzing ? (
            <Loader2 size={20} className="animate-spin text-green-600" />
          ) : (
            <div className="w-8 h-8 bg-green-500/10 rounded-xl flex items-center justify-center text-green-600 group-hover:scale-110 transition-transform">
              <Sparkles size={18} strokeWidth={2.5} />
            </div>
          )}
          <div className="flex flex-col items-start">
            <span className="tracking-tight leading-none">
              {isAnalyzing ? 'AI is Analyzing Body...' : 'AI Body Scan'}
            </span>
            {!isAnalyzing && (
              <span className="text-[8px] font-black uppercase tracking-widest text-green-500/60 mt-1">
                Powered by Gemini 3.1 Pro
              </span>
            )}
          </div>
        </button>
        <input type="file" ref={bodyInputRef} onChange={handleBodyImageChange} accept="image/*" className="hidden" />
      </div>

      {/* Nutritional Goals Card - Always Visible */}
      <div className="glass-card p-8 rounded-[40px] space-y-6 ios-shadow relative overflow-hidden">
        <div className="absolute top-0 right-0 p-6 opacity-[0.03] pointer-events-none">
          <Target size={120} className="text-blue-600" />
        </div>

        <div className="flex items-center justify-between relative z-10">
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-blue-500 rounded-full animate-pulse" />
            <h3 className="text-xs font-bold text-gray-400 uppercase tracking-widest">Nutritional Goals</h3>
          </div>
          <div className="flex items-center gap-1 text-gray-400">
            <Flame size={14} className="text-red-500" />
            <span className="text-xs font-black">{formData.calorieLimit} kcal</span>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-4 relative z-10">
          {[
            { label: 'Protein', value: formData.proteinGoal, pct: formData.proteinPct, color: 'text-blue-500', bg: 'bg-blue-50/50', icon: Beef },
            { label: 'Carbs', value: formData.carbsGoal, pct: formData.carbsPct, color: 'text-orange-500', bg: 'bg-orange-50/50', icon: Wheat },
            { label: 'Fats', value: formData.fatsGoal, pct: formData.fatsPct, color: 'text-purple-500', bg: 'bg-purple-50/50', icon: Droplets }
          ].map((macro) => (
            <div key={macro.label} className={cn("p-4 rounded-2xl border border-white/50 ios-shadow text-center space-y-1", macro.bg)}>
              <div className={cn("w-8 h-8 rounded-xl flex items-center justify-center mx-auto mb-2", macro.color, "bg-white/50")}>
                <macro.icon size={16} />
              </div>
              <p className="text-[8px] font-black text-gray-400 uppercase tracking-widest">{macro.label}</p>
              <p className="text-lg font-black text-gray-900 leading-none">{macro.value}g</p>
              <p className={cn("text-[10px] font-bold", macro.color)}>{macro.pct}%</p>
            </div>
          ))}
        </div>
      </div>

      {/* Editable Fields */}
      <AnimatePresence>
        {isEditing && (
          <motion.div 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 20 }}
            className="space-y-6"
          >
            <div className="grid grid-cols-2 gap-4">
              {/* Height */}
              <div className={cn(
                "glass-card p-5 rounded-[32px] space-y-2 ios-shadow border transition-colors",
                errors.height ? "border-red-500 bg-red-50/10" : "border-white/50"
              )}>
                <div className="flex items-center gap-2 text-blue-500">
                  <Ruler size={16} strokeWidth={2.5} />
                  <p className="text-[10px] font-bold uppercase tracking-widest text-gray-400">Height (cm)</p>
                </div>
                <input 
                  type="number" 
                  value={formData.height}
                  onChange={(e) => handleInputChange('height', parseInt(e.target.value) || 0)}
                  className="text-xl font-bold text-gray-900 w-full bg-transparent focus:outline-none"
                />
                {errors.height && <p className="text-[8px] font-bold text-red-500 uppercase tracking-widest">{errors.height}</p>}
              </div>

              {/* Weight */}
              <div className={cn(
                "glass-card p-5 rounded-[32px] space-y-2 ios-shadow border transition-colors",
                errors.weight ? "border-red-500 bg-red-50/10" : "border-white/50"
              )}>
                <div className="flex items-center gap-2 text-orange-500">
                  <Scale size={16} strokeWidth={2.5} />
                  <p className="text-[10px] font-bold uppercase tracking-widest text-gray-400">Weight (kg)</p>
                </div>
                <input 
                  type="number" 
                  value={formData.weight}
                  onChange={(e) => handleInputChange('weight', parseInt(e.target.value) || 0)}
                  className="text-xl font-bold text-gray-900 w-full bg-transparent focus:outline-none"
                />
                {errors.weight && <p className="text-[8px] font-bold text-red-500 uppercase tracking-widest">{errors.weight}</p>}
              </div>
            </div>

            {/* Goal Selector */}
            <div className="glass-card p-5 rounded-[32px] space-y-2 ios-shadow">
              <div className="flex items-center gap-2 text-purple-500">
                <Target size={16} strokeWidth={2.5} />
                <p className="text-[10px] font-bold uppercase tracking-widest text-gray-400">Your Goal</p>
              </div>
              <select 
                value={formData.goal}
                onChange={(e) => handleInputChange('goal', e.target.value)}
                className="text-xl font-bold text-gray-900 w-full bg-transparent focus:outline-none appearance-none cursor-pointer"
              >
                <option value="lose">Lose Weight</option>
                <option value="maintain">Maintain Weight</option>
                <option value="gain">Gain Weight</option>
              </select>
            </div>

            {/* Calorie Limit Slider */}
            <div className={cn(
              "glass-card p-6 rounded-[32px] space-y-6 ios-shadow border transition-colors",
              errors.calorieLimit ? "border-red-500 bg-red-50/10" : "border-white/50"
            )}>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2 text-red-500">
                  <Flame size={20} strokeWidth={2.5} />
                  <h4 className="font-bold text-gray-800 tracking-tight">Daily Calorie Limit</h4>
                </div>
                <span className="text-xl font-black text-gray-900">{formData.calorieLimit} <span className="text-xs text-gray-400 font-bold uppercase">kcal</span></span>
              </div>
              <input 
                type="range" 
                min="1000" 
                max="5000" 
                step="50"
                value={formData.calorieLimit}
                onChange={(e) => handleInputChange('calorieLimit', parseInt(e.target.value))}
                className="w-full h-2 bg-gray-100 rounded-lg appearance-none cursor-pointer accent-green-600"
              />
              {errors.calorieLimit && <p className="text-[8px] font-bold text-red-500 uppercase tracking-widest">{errors.calorieLimit}</p>}
            </div>

            {/* Water Goal Slider */}
            <div className={cn(
              "glass-card p-6 rounded-[32px] space-y-6 ios-shadow border transition-colors",
              errors.waterGoal ? "border-red-500 bg-red-50/10" : "border-white/50"
            )}>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2 text-blue-500">
                  <Droplets size={20} strokeWidth={2.5} />
                  <h4 className="font-bold text-gray-800 tracking-tight">Water Goal</h4>
                </div>
                <span className="text-xl font-black text-gray-900">{formData.waterGoal} <span className="text-xs text-gray-400 font-bold uppercase">ml</span></span>
              </div>
              <input 
                type="range" 
                min="500" 
                max="10000" 
                step="100"
                value={formData.waterGoal}
                onChange={(e) => handleInputChange('waterGoal', parseInt(e.target.value))}
                className="w-full h-2 bg-gray-100 rounded-lg appearance-none cursor-pointer accent-blue-500"
              />
              {errors.waterGoal && <p className="text-[8px] font-bold text-red-500 uppercase tracking-widest">{errors.waterGoal}</p>}
            </div>

            {/* Reminders Section */}
            <div className="glass-card p-8 rounded-[40px] space-y-6 ios-shadow">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2 text-green-600">
                  <Bell size={20} strokeWidth={2.5} />
                  <h3 className="font-bold text-gray-800 tracking-tight">Reminders</h3>
                </div>
                <button 
                  onClick={addReminder}
                  className="w-8 h-8 bg-green-500/10 rounded-xl flex items-center justify-center text-green-600 ios-tap"
                >
                  <Plus size={18} strokeWidth={2.5} />
                </button>
              </div>

              <div className="space-y-4">
                {formData.reminders.map((reminder) => (
                  <div key={reminder.id} className="flex items-center justify-between glass p-4 rounded-2xl ios-shadow border border-white/50">
                    <div className="flex items-center gap-4">
                      <div className={cn(
                        "w-10 h-10 rounded-xl flex items-center justify-center",
                        reminder.type === 'meal' ? "bg-orange-500/10 text-orange-500" : "bg-blue-500/10 text-blue-500"
                      )}>
                        {reminder.type === 'meal' ? <Beef size={18} /> : <Droplets size={18} />}
                      </div>
                      <div className="flex flex-col">
                        <div className="flex items-center gap-2">
                          <input 
                            type="time" 
                            value={reminder.time}
                            onChange={(e) => updateReminder(reminder.id, { time: e.target.value })}
                            className="font-bold text-gray-900 bg-transparent focus:outline-none"
                          />
                          <select
                            value={reminder.type}
                            onChange={(e) => updateReminder(reminder.id, { type: e.target.value as any })}
                            className="text-[10px] font-bold text-gray-400 uppercase tracking-widest bg-transparent focus:outline-none cursor-pointer"
                          >
                            <option value="meal">Meal</option>
                            <option value="water">Water</option>
                          </select>
                        </div>
                      </div>
                    </div>
                    <div className="flex items-center gap-3">
                      <button 
                        onClick={() => toggleReminder(reminder.id)}
                        className={cn(
                          "w-10 h-5 rounded-full transition-all relative",
                          reminder.enabled ? "bg-green-500" : "bg-gray-200"
                        )}
                      >
                        <div className={cn(
                          "absolute top-0.5 w-4 h-4 bg-white rounded-full transition-all shadow-sm",
                          reminder.enabled ? "left-5.5" : "left-0.5"
                        )} />
                      </button>
                      <button 
                        onClick={() => removeReminder(reminder.id)}
                        className="text-red-400 hover:text-red-500 transition-colors"
                      >
                        <X size={18} />
                      </button>
                    </div>
                  </div>
                ))}
                {formData.reminders.length === 0 && (
                  <p className="text-center text-gray-400 text-xs py-4">No reminders set. Add one to stay on track!</p>
                )}
              </div>
            </div>

            {/* Macro Goals */}
            <div className="grid grid-cols-1 gap-4">
              <div className={cn(
                "px-4 py-2 rounded-2xl text-center font-bold text-[10px] uppercase tracking-widest transition-all",
                (formData.proteinPct + formData.carbsPct + formData.fatsPct) === 100 
                  ? "bg-green-50 text-green-600 border border-green-100" 
                  : "bg-red-50 text-red-600 border border-red-100 animate-pulse"
              )}>
                Macros Sum: {formData.proteinPct + formData.carbsPct + formData.fatsPct}% 
                {(formData.proteinPct + formData.carbsPct + formData.fatsPct) !== 100 && " (Must be 100%)"}
              </div>

              {/* Protein Goal */}
              <div className={cn(
                "glass-card p-6 rounded-[32px] space-y-4 ios-shadow border transition-colors",
                errors.proteinGoal ? "border-red-500 bg-red-50/10" : "border-white/50"
              )}>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2 text-blue-500">
                    <Beef size={20} strokeWidth={2.5} />
                    <h4 className="font-bold text-gray-800 tracking-tight">Protein</h4>
                  </div>
                  <div className="text-right">
                    <p className="text-xl font-black text-gray-900 leading-none">{formData.proteinGoal} <span className="text-[10px] text-gray-400 font-bold uppercase">g</span></p>
                    <p className="text-[10px] font-black text-blue-500 uppercase tracking-widest mt-1">{formData.proteinPct}% of total</p>
                  </div>
                </div>
                <input 
                  type="range" 
                  min="0" 
                  max="100" 
                  step="1"
                  value={formData.proteinPct}
                  onChange={(e) => handleInputChange('proteinPct', parseInt(e.target.value))}
                  className="w-full h-2 bg-gray-100 rounded-lg appearance-none cursor-pointer accent-blue-500"
                />
              </div>

              {/* Carbs Goal */}
              <div className={cn(
                "glass-card p-6 rounded-[32px] space-y-4 ios-shadow border transition-colors",
                errors.carbsGoal ? "border-red-500 bg-red-50/10" : "border-white/50"
              )}>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2 text-orange-500">
                    <Wheat size={20} strokeWidth={2.5} />
                    <h4 className="font-bold text-gray-800 tracking-tight">Carbs</h4>
                  </div>
                  <div className="text-right">
                    <p className="text-xl font-black text-gray-900 leading-none">{formData.carbsGoal} <span className="text-[10px] text-gray-400 font-bold uppercase">g</span></p>
                    <p className="text-[10px] font-black text-orange-500 uppercase tracking-widest mt-1">{formData.carbsPct}% of total</p>
                  </div>
                </div>
                <input 
                  type="range" 
                  min="0" 
                  max="100" 
                  step="1"
                  value={formData.carbsPct}
                  onChange={(e) => handleInputChange('carbsPct', parseInt(e.target.value))}
                  className="w-full h-2 bg-gray-100 rounded-lg appearance-none cursor-pointer accent-orange-500"
                />
              </div>

              {/* Fats Goal */}
              <div className={cn(
                "glass-card p-6 rounded-[32px] space-y-4 ios-shadow border transition-colors",
                errors.fatsGoal ? "border-red-500 bg-red-50/10" : "border-white/50"
              )}>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2 text-purple-500">
                    <Droplets size={20} strokeWidth={2.5} />
                    <h4 className="font-bold text-gray-800 tracking-tight">Fats</h4>
                  </div>
                  <div className="text-right">
                    <p className="text-xl font-black text-gray-900 leading-none">{formData.fatsGoal} <span className="text-[10px] text-gray-400 font-bold uppercase">g</span></p>
                    <p className="text-[10px] font-black text-purple-500 uppercase tracking-widest mt-1">{formData.fatsPct}% of total</p>
                  </div>
                </div>
                <input 
                  type="range" 
                  min="0" 
                  max="100" 
                  step="1"
                  value={formData.fatsPct}
                  onChange={(e) => handleInputChange('fatsPct', parseInt(e.target.value))}
                  className="w-full h-2 bg-gray-100 rounded-lg appearance-none cursor-pointer accent-purple-500"
                />
              </div>
            </div>

            <div className="flex gap-4 pt-4">
              <button 
                onClick={() => {
                  triggerHaptic(hapticPatterns.light);
                  setIsEditing(false);
                  setFormData(initialData); // Reset changes on cancel
                  setErrors({});
                }}
                className="flex-1 py-4 glass rounded-2xl font-bold text-gray-500 hover:bg-gray-50 transition-all ios-shadow ios-tap"
              >
                Cancel
              </button>
              <button 
                onClick={handleSave}
                disabled={!isDirty}
                className={cn(
                  "flex-2 py-4 rounded-2xl font-bold transition-all flex items-center justify-center gap-3 ios-tap",
                  isDirty 
                    ? "bg-green-600 text-white shadow-xl shadow-green-600/20 hover:bg-green-700" 
                    : "bg-gray-100 text-gray-400 cursor-not-allowed"
                )}
              >
                <Save size={20} strokeWidth={2.5} />
                Save Changes
              </button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      <button 
        onClick={handleSignOut}
        className="w-full py-5 flex items-center justify-center gap-3 text-red-500 font-bold glass hover:bg-red-50 rounded-[32px] transition-all ios-shadow"
      >
        <LogOut size={20} strokeWidth={2.5} />
        Sign Out
      </button>

      <div className="pt-4">
        <button 
          onClick={() => setShowClearConfirm(true)}
          className="w-full py-5 flex items-center justify-center gap-3 text-gray-400 hover:text-red-500 font-bold glass hover:bg-red-50/10 rounded-[32px] transition-all ios-shadow"
        >
          <Trash2 size={20} strokeWidth={2.5} />
          Clear AI Chat History
        </button>
      </div>

      {/* Confirmation Modal */}
      <AnimatePresence>
        {showClearConfirm && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-6">
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setShowClearConfirm(false)}
              className="absolute inset-0 bg-black/40 backdrop-blur-sm"
            />
            <motion.div 
              initial={{ opacity: 0, scale: 0.9, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.9, y: 20 }}
              className="glass-card w-full max-w-sm p-8 rounded-[40px] ios-shadow relative z-10 space-y-6"
            >
              <div className="w-16 h-16 bg-red-500/10 rounded-3xl flex items-center justify-center text-red-500 mx-auto">
                <Trash2 size={32} />
              </div>
              <div className="text-center space-y-2">
                <h3 className="text-xl font-bold text-gray-900">Clear Chat History?</h3>
                <p className="text-sm text-gray-500 leading-relaxed">This will permanently delete all your conversations with the AI Coach. This action cannot be undone.</p>
              </div>
              <div className="flex gap-3">
                <button 
                  onClick={() => setShowClearConfirm(false)}
                  className="flex-1 py-4 glass rounded-2xl font-bold text-gray-500 ios-tap"
                >
                  Cancel
                </button>
                <button 
                  onClick={handleClearChat}
                  disabled={isClearing}
                  className="flex-1 py-4 bg-red-500 text-white rounded-2xl font-bold shadow-lg shadow-red-500/20 ios-tap flex items-center justify-center gap-2"
                >
                  {isClearing ? <Loader2 size={20} className="animate-spin" /> : 'Clear All'}
                </button>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

      {/* BMI Info Modal */}
      <AnimatePresence>
        {showBMIInfo && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-6">
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setShowBMIInfo(false)}
              className="absolute inset-0 bg-black/40 backdrop-blur-sm"
            />
            <motion.div 
              initial={{ opacity: 0, scale: 0.9, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.9, y: 20 }}
              className="glass-card w-full max-w-sm p-8 rounded-[40px] ios-shadow relative z-10 space-y-6"
            >
              <div className="flex items-center justify-between">
                <h3 className="text-xl font-bold text-gray-900">BMI Categories</h3>
                <button onClick={() => setShowBMIInfo(false)} className="text-gray-400 hover:text-gray-600">
                  <X size={20} />
                </button>
              </div>
              <div className="space-y-4">
                {[
                  { range: '< 18.5', label: 'Underweight', color: 'text-blue-500', bg: 'bg-blue-50' },
                  { range: '18.5 - 24.9', label: 'Healthy', color: 'text-green-600', bg: 'bg-green-50' },
                  { range: '25.0 - 29.9', label: 'Overweight', color: 'text-orange-500', bg: 'bg-orange-50' },
                  { range: '≥ 30.0', label: 'Obese', color: 'text-red-500', bg: 'bg-red-50' }
                ].map((cat) => (
                  <div key={cat.label} className={cn("flex items-center justify-between p-4 rounded-2xl border border-white/50", cat.bg)}>
                    <span className={cn("font-bold", cat.color)}>{cat.label}</span>
                    <span className="text-xs font-black text-gray-400 uppercase tracking-widest">{cat.range}</span>
                  </div>
                ))}
              </div>
              <p className="text-[10px] text-gray-400 leading-relaxed text-center font-medium">
                BMI is a simple index of weight-for-height that is commonly used to classify underweight, overweight and obesity in adults.
              </p>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
};

export default SettingsScreen;
