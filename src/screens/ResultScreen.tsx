import React from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { ChevronLeft, Share2, Check, Flame, Beef, Wheat, Droplets, Info, User, Dog, Fingerprint } from 'lucide-react';
import { motion } from 'motion/react';
import { ScanResult } from '../types';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { useUser } from '../contexts/UserContext';

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
          onClick={() => navigate('/')}
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
    if (navigator.share) {
      try {
        await navigator.share({
          title: `NutriSnap - ${scan.foodName}`,
          text: `Check out my ${scan.foodName} scan on NutriSnap!`,
          url: window.location.href,
        });
      } catch (error) {
        console.error('Error sharing:', error);
      }
    } else {
      try {
        await navigator.clipboard.writeText(window.location.href);
        triggerHaptic(hapticPatterns.success);
      } catch (err) {
        console.error('Failed to copy:', err);
      }
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
      <div className="space-y-10">
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
              <div className="space-y-4">
                <p>
                  Our AI has identified this as a <span className="text-green-600 font-bold capitalize">{scan.type}</span>. 
                  {scan.type === 'person' ? ` It appears to be a ${scan.details}.` : scan.type === 'animal' ? ` It appears to be a ${scan.details}.` : ''}
                </p>
                <div className="p-4 bg-gray-50/50 rounded-2xl border border-gray-100 italic text-base">
                  "{scan.description}"
                </div>
                <p className="text-sm text-gray-400">
                  NutriSnap is primarily designed for food tracking, but we can recognize other objects to help you organize your gallery.
                </p>
              </div>
            )}
          </div>
        </div>

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
