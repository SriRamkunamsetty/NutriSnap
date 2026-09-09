import React, { useState, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  Camera, 
  Activity, 
  Sparkles, 
  X, 
  Check, 
  Loader2, 
  Dumbbell, 
  Zap, 
  ShieldCheck, 
  ArrowRight,
  User,
  Heart,
  AlertCircle
} from 'lucide-react';
import { useUser } from '../contexts/UserContext';
import { analyzeBodyImage } from '../services/geminiService';
import { saveScanResult, saveUserProfile, compressImage } from '../services/storageService';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { cn } from '../lib/utils';

interface BodyScanModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const BodyScanModal: React.FC<BodyScanModalProps> = ({ isOpen, onClose }) => {
  const { profile, updateProfile, refreshProfile } = useUser();
  const [selectedImage, setSelectedImage] = useState<string | null>(null);
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [analysisResult, setAnalysisResult] = useState<any>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [isSavedSuccess, setIsSavedSuccess] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  if (!isOpen) return null;

  const handleImagePick = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    triggerHaptic(hapticPatterns.light);
    setIsAnalyzing(true);
    setSaveError(null);

    try {
      // Compress immediately so we have a light, high quality dataUrl that fits in local storage
      const compressedDataUrl = await compressImage(file, 800, 800, 0.75);
      setSelectedImage(compressedDataUrl);
      triggerHaptic(hapticPatterns.medium);

      const base64 = compressedDataUrl.split(',')[1];
      const result = await analyzeBodyImage(base64, 'image/jpeg', profile || undefined);
      setAnalysisResult(result);
      triggerHaptic(hapticPatterns.success);
    } catch (err) {
      console.error('Body analysis error', err);
      triggerHaptic(hapticPatterns.error);
    } finally {
      setIsAnalyzing(false);
    }
  };

  const handleSaveToProfile = async () => {
    if (!analysisResult) return;
    setIsSaving(true);
    setSaveError(null);
    triggerHaptic(hapticPatterns.medium);

    try {
      // Ensure image is compressed and optimized for localStorage
      const finalImage = selectedImage ? await compressImage(selectedImage, 700, 700, 0.7) : undefined;

      // 1. Update user profile metrics AND body scan image in context & persistent storage
      await updateProfile({
        bodyType: analysisResult.bodyType,
        fatEstimate: analysisResult.fatEstimate,
        muscleMass: analysisResult.muscleMass,
        fitnessLevel: analysisResult.fitnessLevel,
        bodyScanURL: finalImage,
        localBodyScanPath: finalImage,
      });

      // 2. Also directly ensure saveUserProfile is called with the image
      await saveUserProfile({
        bodyType: analysisResult.bodyType,
        fatEstimate: analysisResult.fatEstimate,
        muscleMass: analysisResult.muscleMass,
        fitnessLevel: analysisResult.fitnessLevel,
        bodyScanURL: finalImage,
        localBodyScanPath: finalImage,
      });

      // 3. Save to local scans history so it shows on Body Fat Trend chart
      await saveScanResult({
        foodName: `Body Scan (${analysisResult.fitnessLevel})`,
        type: 'person',
        calories: 0,
        protein: 0,
        carbs: 0,
        fats: 0,
        fatEstimate: analysisResult.fatEstimate,
        details: `${analysisResult.bodyType} somatotype, ~${analysisResult.muscleMass}kg lean muscle`,
        description: analysisResult.muscleObservations,
        imageUrl: finalImage,
        localImagePath: finalImage,
        confidence: 0.95,
      });

      // 4. Trigger context profile refresh
      await refreshProfile();

      setIsSavedSuccess(true);
      triggerHaptic(hapticPatterns.success);
      setTimeout(() => {
        setIsSavedSuccess(false);
        onClose();
      }, 1200);
    } catch (e: any) {
      console.error('Failed to save body scan', e);
      setSaveError('Could not save to local storage. Please try again.');
      triggerHaptic(hapticPatterns.error);
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-[100] bg-black/60 backdrop-blur-md flex items-end sm:items-center justify-center p-4">
      <motion.div
        initial={{ opacity: 0, y: 50 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: 50 }}
        className="bg-white rounded-[36px] w-full max-w-lg overflow-hidden shadow-2xl border border-gray-100 flex flex-col max-h-[92vh]"
      >
        {/* Header */}
        <div className="p-6 bg-gradient-to-r from-purple-600 to-indigo-700 text-white flex justify-between items-start">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-2xl bg-white/20 flex items-center justify-center text-white backdrop-blur-sm">
              <Activity size={24} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-xl font-black">Two-Layer AI Body Scan</h3>
                <span className="text-[10px] font-black uppercase tracking-wider bg-white/25 px-2 py-0.5 rounded-full">
                  ML + Vision
                </span>
              </div>
              <p className="text-xs text-white/80">
                Anthropometric formula + Gemini Vision posture & body fat calibration
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="w-8 h-8 rounded-full bg-white/20 hover:bg-white/30 text-white flex items-center justify-center transition-colors"
          >
            <X size={18} />
          </button>
        </div>

        {/* Content */}
        <div className="p-6 overflow-y-auto space-y-5 flex-1">
          {/* If no image selected yet */}
          {!selectedImage && (
            <div className="py-8 text-center space-y-5">
              <div className="w-20 h-20 bg-purple-50 text-purple-600 rounded-3xl mx-auto flex items-center justify-center shadow-inner">
                <Camera size={38} />
              </div>
              <div className="space-y-1 max-w-xs mx-auto">
                <h4 className="text-lg font-bold text-gray-900">Take or Upload Full Body Photo</h4>
                <p className="text-xs text-gray-500 leading-relaxed">
                  Stand upright in fitted clothing or athletic wear against good lighting for accurate posture and body fat calibration.
                </p>
              </div>

              <div className="p-4 rounded-2xl bg-purple-50/60 border border-purple-100 text-left space-y-2 text-xs text-purple-900">
                <div className="flex items-center gap-2 font-bold">
                  <ShieldCheck size={16} className="text-purple-600" />
                  <span>100% On-Device & Private</span>
                </div>
                <p className="text-[11px] text-purple-800/80 leading-relaxed">
                  Your body photos are never stored in external cloud storage. Analysis occurs locally.
                </p>
              </div>

              <input
                type="file"
                ref={fileInputRef}
                accept="image/*"
                onChange={handleImagePick}
                className="hidden"
              />

              <button
                onClick={() => fileInputRef.current?.click()}
                className="w-full py-4 bg-purple-600 hover:bg-purple-700 text-white rounded-2xl font-bold shadow-lg shadow-purple-600/25 flex items-center justify-center gap-2 transition-all"
              >
                <Camera size={18} />
                <span>Snap or Choose Photo</span>
              </button>
            </div>
          )}

          {/* Analyzing Spinner */}
          {selectedImage && isAnalyzing && (
            <div className="py-12 text-center space-y-4">
              <div className="relative w-20 h-20 mx-auto">
                <div className="w-20 h-20 border-4 border-purple-500/20 rounded-full absolute inset-0" />
                <div className="w-20 h-20 border-4 border-purple-600 border-t-transparent rounded-full animate-spin" />
              </div>
              <div className="space-y-1">
                <h4 className="text-base font-bold text-gray-900">
                  Calibrating Body Composition
                </h4>
                <p className="text-xs text-gray-500">
                  Calculating Boer lean mass, Deurenberg body fat %, & Gemini visual cues...
                </p>
              </div>
            </div>
          )}

          {/* Results display */}
          {analysisResult && !isAnalyzing && (
            <div className="space-y-4">
              {/* Photo & Top Metrics */}
              <div className="flex items-center gap-4 p-4 rounded-2xl bg-purple-50/70 border border-purple-100">
                {selectedImage && (
                  <img
                    src={selectedImage}
                    alt="Body Preview"
                    className="w-20 h-24 rounded-xl object-cover shadow-sm border border-white"
                  />
                )}
                <div className="space-y-1.5 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-black uppercase tracking-wider text-purple-700 bg-white px-2 py-0.5 rounded-full border border-purple-200">
                      {analysisResult.bodyType}
                    </span>
                    <span className="text-xs font-bold text-gray-600">
                      {analysisResult.fitnessLevel}
                    </span>
                  </div>
                  <div className="flex gap-4 pt-1">
                    <div>
                      <span className="text-[10px] font-bold text-gray-400 uppercase block">Body Fat</span>
                      <span className="text-xl font-black text-purple-700">
                        {analysisResult.fatEstimate}%
                      </span>
                    </div>
                    <div className="border-l border-purple-200 pl-4">
                      <span className="text-[10px] font-bold text-gray-400 uppercase block">Muscle Mass</span>
                      <span className="text-xl font-black text-gray-900">
                        {analysisResult.muscleMass} <span className="text-xs font-normal">kg</span>
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              {/* Observations */}
              <div className="p-4 rounded-2xl bg-gray-50 border border-gray-100 space-y-1.5">
                <h5 className="text-xs font-bold text-gray-700 uppercase tracking-wider flex items-center gap-1.5">
                  <Sparkles size={14} className="text-purple-600" />
                  Posture & Silhouette Observations
                </h5>
                <p className="text-xs text-gray-600 leading-relaxed">
                  {analysisResult.muscleObservations}
                </p>
              </div>

              {/* Weekly Workout Plan */}
              <div className="p-4 rounded-2xl bg-gray-50 border border-gray-100 space-y-1.5">
                <h5 className="text-xs font-bold text-gray-700 uppercase tracking-wider flex items-center gap-1.5">
                  <Dumbbell size={14} className="text-purple-600" />
                  Targeted Training Strategy
                </h5>
                <p className="text-xs text-gray-600 leading-relaxed">
                  {analysisResult.weeklyPlan}
                </p>
              </div>

              {/* Nutrition Adjustments */}
              <div className="p-4 rounded-2xl bg-gray-50 border border-gray-100 space-y-2">
                <h5 className="text-xs font-bold text-gray-700 uppercase tracking-wider flex items-center gap-1.5">
                  <Zap size={14} className="text-amber-500" />
                  3 Tactical Nutrition Tweaks
                </h5>
                <ul className="space-y-1.5">
                  {analysisResult.nutritionAdjustments?.map((adj: string, i: number) => (
                    <li key={i} className="text-xs text-gray-600 flex items-start gap-2">
                      <Check size={14} className="text-emerald-600 shrink-0 mt-0.5" />
                      <span>{adj}</span>
                    </li>
                  ))}
                </ul>
              </div>

              <div className="pt-2 flex gap-3">
                <button
                  type="button"
                  onClick={() => {
                    setSelectedImage(null);
                    setAnalysisResult(null);
                  }}
                  className="w-1/3 py-3.5 rounded-2xl bg-gray-100 hover:bg-gray-200 text-gray-700 text-xs font-bold transition-all"
                >
                  Retake
                </button>
                <button
                  type="button"
                  disabled={isSaving || isSavedSuccess}
                  onClick={handleSaveToProfile}
                  className={cn(
                    "flex-1 py-3.5 rounded-2xl text-white text-xs font-bold shadow-lg flex items-center justify-center gap-1.5 transition-all duration-300",
                    isSavedSuccess
                      ? "bg-emerald-600 shadow-emerald-600/25"
                      : "bg-purple-600 hover:bg-purple-700 shadow-purple-600/25"
                  )}
                >
                  {isSaving ? (
                    <>
                      <Loader2 size={16} className="animate-spin" />
                      <span>Updating Profile & History...</span>
                    </>
                  ) : isSavedSuccess ? (
                    <>
                      <Check size={16} strokeWidth={3} className="text-white animate-bounce" />
                      <span>Updated & Saved!</span>
                    </>
                  ) : (
                    <>
                      <span>Apply to Profile & History</span>
                      <ArrowRight size={15} />
                    </>
                  )}
                </button>
              </div>

              {saveError && (
                <div className="p-3 rounded-2xl bg-rose-50 border border-rose-200 text-rose-700 text-xs font-medium flex items-center gap-2">
                  <AlertCircle size={16} className="shrink-0 text-rose-600" />
                  <span>{saveError}</span>
                </div>
              )}
            </div>
          )}
        </div>
      </motion.div>
    </div>
  );
};
