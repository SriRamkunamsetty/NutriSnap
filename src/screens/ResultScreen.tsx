import React from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { ChevronLeft, Share2, Check, Flame, Beef, Wheat, Droplets, Info } from 'lucide-react';
import { motion } from 'motion/react';
import { ScanResult } from '../types';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { useUser } from '../contexts/UserContext';

const ResultScreen: React.FC = () => {
  const { state } = useLocation();
  const navigate = useNavigate();
  const { id } = useParams();
  const { scans } = useUser();
  
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

  const macros = [
    { label: 'Protein', value: scan.protein, unit: 'g', icon: Beef, color: 'bg-blue-500', textColor: 'text-blue-600', bgColor: 'bg-blue-50/50' },
    { label: 'Carbs', value: scan.carbs, unit: 'g', icon: Wheat, color: 'bg-orange-500', textColor: 'text-orange-600', bgColor: 'bg-orange-50/50' },
    { label: 'Fats', value: scan.fats, unit: 'g', icon: Droplets, color: 'bg-purple-500', textColor: 'text-purple-600', bgColor: 'bg-purple-50/50' },
  ];

  return (
    <div className="flex flex-col min-h-full pb-10">
      {/* Top Image Section */}
      <div className="relative h-[480px] w-full -mx-6 -mt-6 mb-10 overflow-hidden rounded-b-[60px] ios-shadow">
        <img 
          src={scan.imageUrl} 
          alt={scan.foodName} 
          className="w-full h-full object-cover"
          referrerPolicy="no-referrer"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-black/90 via-black/30 to-transparent" />
        
        <button 
          onClick={() => navigate('/')}
          className="absolute top-8 left-8 w-12 h-12 glass rounded-2xl flex items-center justify-center text-white hover:bg-white/30 transition-all border border-white/20 ios-shadow"
        >
          <ChevronLeft size={24} strokeWidth={2.5} />
        </button>
        
        <button 
          className="absolute top-8 right-8 w-12 h-12 glass rounded-2xl flex items-center justify-center text-white hover:bg-white/30 transition-all border border-white/20 ios-shadow"
        >
          <Share2 size={20} strokeWidth={2.5} />
        </button>

        <div className="absolute bottom-16 left-10 right-10">
          <motion.div 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="space-y-5"
          >
            <div className="flex items-center gap-3">
              <span className="bg-green-500 text-white text-[10px] font-black px-4 py-1.5 rounded-full uppercase tracking-[0.2em] shadow-xl shadow-green-500/30">
                AI Verified
              </span>
              <span className="text-white/70 text-xs font-bold uppercase tracking-[0.2em]">
                {new Date(scan.timestamp).toLocaleDateString([], { month: 'short', day: 'numeric' })}
              </span>
            </div>
            
            <div className="flex items-end justify-between gap-6">
              <h1 className="text-5xl font-black text-white tracking-tighter leading-none flex-1">
                {scan.foodName}
              </h1>
              <div className="glass text-white px-8 py-4 rounded-[32px] font-black shadow-2xl flex items-center gap-3 flex-shrink-0 border border-white/20">
                <Flame size={24} className="text-orange-500" strokeWidth={2.5} />
                <div className="flex flex-col leading-none">
                  <span className="text-2xl">{scan.calories}</span>
                  <span className="text-[10px] font-black text-white/60 uppercase tracking-widest mt-1">kcal</span>
                </div>
              </div>
            </div>
          </motion.div>
        </div>
      </div>

      {/* Content Section */}
      <div className="space-y-10">
        <div className="space-y-6">
          <h3 className="text-[10px] font-bold uppercase tracking-[0.2em] text-gray-400 px-2">Nutritional Breakdown</h3>
          <div className="grid grid-cols-3 gap-4">
            {macros.map((macro, idx) => (
              <motion.div 
                key={macro.label}
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={{ delay: idx * 0.1 }}
                className={`glass-card p-6 rounded-[40px] flex flex-col items-center gap-4 border border-white/50 ios-shadow`}
              >
                <div className={`${macro.color} w-14 h-14 rounded-2xl flex items-center justify-center text-white shadow-xl`}>
                  <macro.icon size={28} strokeWidth={2.5} />
                </div>
                <div className="text-center space-y-1">
                  <p className={`text-2xl font-black text-gray-900 tracking-tight`}>{macro.value}<span className="text-xs ml-0.5 font-bold text-gray-400">{macro.unit}</span></p>
                  <p className="text-[10px] font-black uppercase tracking-widest text-gray-400">{macro.label}</p>
                </div>
              </motion.div>
            ))}
          </div>
        </div>

        <div className="glass-card p-10 rounded-[48px] ios-shadow space-y-6 relative overflow-hidden">
          <div className="absolute top-0 right-0 p-8 opacity-[0.03] pointer-events-none">
            <Check size={120} className="text-green-600" />
          </div>
          <div className="flex items-center gap-3 relative z-10">
            <div className="w-10 h-10 bg-green-500/10 rounded-2xl flex items-center justify-center text-green-600">
              <Check size={20} strokeWidth={2.5} />
            </div>
            <h3 className="text-xl font-bold tracking-tight">AI Health Insight</h3>
          </div>
          <p className="text-gray-600 leading-relaxed font-medium relative z-10 text-lg">
            This meal is {scan.protein > 20 ? 'excellent for muscle recovery due to its high protein content' : 'a balanced choice for your daily intake'}. 
            {scan.calories > 800 ? ' It is quite calorie-dense, so consider balancing your next meal with lighter options.' : ' It fits perfectly within your daily calorie budget.'}
          </p>
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
