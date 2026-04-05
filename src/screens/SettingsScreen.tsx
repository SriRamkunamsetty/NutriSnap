import React, { useState, useEffect, useRef } from 'react';
import { User, Scale, Ruler, Target, Flame, Save, LogOut, ChevronRight, Info, Shield, Bell, Activity, Camera, Loader2 } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { auth } from '../firebase';
import { saveUserProfile, uploadProfileImage } from '../services/storageService';
import { analyzeBodyImage } from '../services/geminiService';
import { UserProfile, Goal, BodyType } from '../types';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { useUser } from '../contexts/UserContext';

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
  const bodyInputRef = useRef<HTMLInputElement>(null);
  const profileInputRef = useRef<HTMLInputElement>(null);
  
  const [formData, setFormData] = useState({
    height: 175,
    weight: 70,
    goal: 'maintain' as Goal,
    calorieLimit: 2000,
    displayName: auth.currentUser?.displayName || 'User',
    photoURL: auth.currentUser?.photoURL || '',
    bmi: 22.9,
    bodyType: 'unknown' as BodyType,
    fatEstimate: 0
  });

  useEffect(() => {
    if (profile) {
      setFormData({
        height: profile.height || 175,
        weight: profile.weight || 70,
        goal: profile.goal || 'maintain',
        calorieLimit: profile.calorieLimit || 2000,
        displayName: profile.displayName || auth.currentUser?.displayName || 'User',
        photoURL: profile.photoURL || auth.currentUser?.photoURL || '',
        bmi: profile.bmi || 22.9,
        bodyType: profile.bodyType || 'unknown',
        fatEstimate: profile.fatEstimate || 0
      });
    }
  }, [profile]);

  const calculateBMI = (h: number, w: number) => {
    if (!h || !w) return 0;
    return Math.round((w / Math.pow(h / 100, 2)) * 10) / 10;
  };

  const bmi = calculateBMI(formData.height, formData.weight);
  const bmiCategory = bmi < 18.5 ? 'Underweight' : bmi < 25 ? 'Healthy' : bmi < 30 ? 'Overweight' : 'Obese';

  const handleSave = async () => {
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
    setFormData(prev => ({ ...prev, [field]: value }));
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
        <div className="relative group">
          <button 
            onClick={() => profileInputRef.current?.click()}
            disabled={isUploadingProfile}
            className="w-28 h-28 bg-green-500 rounded-[40px] flex items-center justify-center text-white text-4xl font-bold shadow-2xl shadow-green-500/30 ios-shadow group-hover:scale-105 transition-transform overflow-hidden relative"
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
              <Camera size={24} className="text-white" />
            </div>
          </button>
          <input 
            type="file" 
            ref={profileInputRef} 
            onChange={handleProfileImageChange} 
            accept="image/*" 
            className="hidden" 
          />
          <div className="absolute -bottom-2 -right-2 w-10 h-10 glass rounded-2xl flex items-center justify-center text-green-600 ios-shadow pointer-events-none">
            <User size={20} strokeWidth={2.5} />
          </div>
        </div>
        <div className="space-y-1">
          <h2 className="text-2xl font-bold text-gray-900 tracking-tight">{formData.displayName}</h2>
          <p className="text-sm text-gray-400 font-medium tracking-tight">{auth.currentUser?.email}</p>
        </div>
        {!isEditing && (
          <button 
            onClick={() => setIsEditing(true)}
            className="px-6 py-2 glass rounded-full text-sm font-bold text-green-600 hover:bg-green-50 transition-all ios-shadow"
          >
            Edit Profile
          </button>
        )}
      </div>

      {/* Health Metrics Card */}
      <div className="glass-card p-8 rounded-[40px] space-y-6 ios-shadow relative overflow-hidden">
        <div className="absolute top-0 right-0 p-6 opacity-[0.03] pointer-events-none">
          <Activity size={120} className="text-green-600" />
        </div>

        <div className="flex items-center justify-between relative z-10">
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse" />
            <h3 className="text-xs font-bold text-gray-400 uppercase tracking-widest">Health Index</h3>
          </div>
          <motion.span 
            key={bmiCategory}
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            className={cn(
              "text-[10px] font-black px-3 py-1 rounded-full border uppercase tracking-widest transition-colors",
              bmiCategory === 'Healthy' ? "text-green-600 bg-green-50/50 border-green-100" : "text-orange-600 bg-orange-50/50 border-orange-100"
            )}
          >
            {bmiCategory}
          </motion.span>
        </div>
        
        <div className="flex items-baseline gap-2 relative z-10">
          <motion.span 
            key={bmi}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="text-6xl font-black text-gray-900 tracking-tighter"
          >
            {bmi}
          </motion.span>
          <span className="text-gray-400 font-bold text-sm tracking-tight">BMI</span>
        </div>
        
        <div className="h-2 bg-gray-100/50 rounded-full overflow-hidden border border-white/20 relative z-10">
          <motion.div 
            initial={{ width: 0 }}
            animate={{ width: `${Math.min((bmi / 40) * 100, 100)}%` }}
            className={cn(
              "h-full rounded-full transition-all duration-1000",
              bmiCategory === 'Healthy' ? "bg-green-500" : "bg-orange-500"
            )}
          />
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
              <Camera size={18} strokeWidth={2.5} />
            </div>
          )}
          <span className="tracking-tight">
            {isAnalyzing ? 'AI is Analyzing Body...' : 'AI Body Scan'}
          </span>
        </button>
        <input type="file" ref={bodyInputRef} onChange={handleBodyImageChange} accept="image/*" className="hidden" />
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
              <div className="glass-card p-5 rounded-[32px] space-y-2 ios-shadow">
                <div className="flex items-center gap-2 text-blue-500">
                  <Ruler size={16} strokeWidth={2.5} />
                  <p className="text-[10px] font-bold uppercase tracking-widest text-gray-400">Height (cm)</p>
                </div>
                <input 
                  type="number" 
                  value={formData.height}
                  onChange={(e) => handleInputChange('height', parseInt(e.target.value))}
                  className="text-xl font-bold text-gray-900 w-full bg-transparent focus:outline-none"
                />
              </div>

              {/* Weight */}
              <div className="glass-card p-5 rounded-[32px] space-y-2 ios-shadow">
                <div className="flex items-center gap-2 text-orange-500">
                  <Scale size={16} strokeWidth={2.5} />
                  <p className="text-[10px] font-bold uppercase tracking-widest text-gray-400">Weight (kg)</p>
                </div>
                <input 
                  type="number" 
                  value={formData.weight}
                  onChange={(e) => handleInputChange('weight', parseInt(e.target.value))}
                  className="text-xl font-bold text-gray-900 w-full bg-transparent focus:outline-none"
                />
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
            <div className="glass-card p-6 rounded-[32px] space-y-6 ios-shadow">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2 text-red-500">
                  <Flame size={20} strokeWidth={2.5} />
                  <h4 className="font-bold text-gray-800 tracking-tight">Daily Calorie Limit</h4>
                </div>
                <span className="text-xl font-black text-gray-900">{formData.calorieLimit} <span className="text-xs text-gray-400 font-bold uppercase">kcal</span></span>
              </div>
              <input 
                type="range" 
                min="1200" 
                max="4000" 
                step="50"
                value={formData.calorieLimit}
                onChange={(e) => handleInputChange('calorieLimit', parseInt(e.target.value))}
                className="w-full h-2 bg-gray-100 rounded-lg appearance-none cursor-pointer accent-green-600"
              />
            </div>

            {/* Action Buttons */}
            <div className="flex gap-4 pt-4">
              <button 
                onClick={() => setIsEditing(false)}
                className="flex-1 py-4 glass rounded-2xl font-bold text-gray-500 hover:bg-gray-50 transition-all ios-shadow"
              >
                Cancel
              </button>
              <button 
                onClick={handleSave}
                className="flex-2 py-4 bg-green-600 text-white rounded-2xl font-bold shadow-xl shadow-green-600/20 hover:bg-green-700 transition-all flex items-center justify-center gap-3"
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
    </div>
  );
};

export default SettingsScreen;
