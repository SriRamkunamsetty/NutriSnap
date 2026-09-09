import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { 
  UtensilsCrossed, 
  Sparkles, 
  X, 
  Check, 
  Clock, 
  Flame, 
  Zap, 
  ChevronRight,
  PlusCircle,
  Lightbulb
} from 'lucide-react';
import { useUser } from '../contexts/UserContext';
import { saveScanResult } from '../services/storageService';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';

interface MessOSModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const MessOSModal: React.FC<MessOSModalProps> = ({ isOpen, onClose }) => {
  const { profile } = useUser();
  const [selectedMeal, setSelectedMeal] = useState<'lunch' | 'dinner' | 'breakfast'>('lunch');
  const [loggedToast, setLoggedToast] = useState<string | null>(null);

  if (!isOpen) return null;

  const MESS_MENU = {
    lunch: [
      {
        name: 'Dal Tadka (Double Bowl)',
        calories: 210,
        protein: 16,
        carbs: 28,
        fats: 5,
        hack: 'Ask for minimal tadka oil and grab 2 bowls for 16g clean lentil protein',
        tag: 'High Protein Swap',
      },
      {
        name: 'Roti with Ghee (2 pcs)',
        calories: 180,
        protein: 6,
        carbs: 34,
        fats: 4,
        hack: 'Limit to 2 rotis; prioritize dal and raw cucumber salad first',
        tag: 'Portion Control',
      },
      {
        name: 'Paneer Bhurji / Soya Chunks',
        calories: 260,
        protein: 24,
        carbs: 8,
        fats: 16,
        hack: 'Best mess protein item; pair with cucumber slices',
        tag: 'Champion Pick',
      },
      {
        name: 'Steamed Jeera Rice (Half Plate)',
        calories: 140,
        protein: 3,
        carbs: 30,
        fats: 1,
        hack: 'Eat half plate to keep afternoon sluggishness away',
        tag: 'Clean Carb',
      },
    ],
    dinner: [
      {
        name: 'Mixed Veg / Rajma Curry',
        calories: 240,
        protein: 14,
        carbs: 32,
        fats: 6,
        hack: 'Rajma is rich in potassium and slow-digesting protein',
        tag: 'Fiber Rich',
      },
      {
        name: 'Curd / Buttermilk (Chaach)',
        calories: 80,
        protein: 6,
        carbs: 8,
        fats: 3,
        hack: 'Drink 1 glass of cold chaach with roasted jeera to aid digestion',
        tag: 'Gut Health',
      },
      {
        name: 'Boiled Egg / Egg Curry (2 eggs)',
        calories: 190,
        protein: 18,
        carbs: 4,
        fats: 12,
        hack: 'Take eggs with less gravy to cut hidden mess refined oil',
        tag: 'Lean Protein',
      },
    ],
    breakfast: [
      {
        name: 'Poha with Roasted Peanuts',
        calories: 220,
        protein: 7,
        carbs: 36,
        fats: 7,
        hack: 'Add extra peanuts and lemon for iron absorption',
        tag: 'Energizer',
      },
      {
        name: 'Idli & Sambar (3 pcs)',
        calories: 210,
        protein: 9,
        carbs: 42,
        fats: 2,
        hack: 'Skip white coconut chutney, drink extra bowl of hot sambar',
        tag: 'Low Fat',
      },
      {
        name: 'Omelette with Brown Bread',
        calories: 280,
        protein: 19,
        carbs: 24,
        fats: 12,
        hack: 'Great high-protein campus breakfast',
        tag: 'Recovery',
      },
    ],
  };

  const handleQuickLog = async (item: any) => {
    triggerHaptic(hapticPatterns.medium);
    try {
      await saveScanResult({
        foodName: item.name,
        type: 'food',
        calories: item.calories,
        protein: item.protein,
        carbs: item.carbs,
        fats: item.fats,
        confidence: 0.95,
        details: item.hack,
        description: `Logged from MessOS Campus Assistant (${selectedMeal})`,
      });
      setLoggedToast(`Logged ${item.name} (+${item.calories} kcal)`);
      setTimeout(() => setLoggedToast(null), 2500);
    } catch (e) {
      console.error('Failed to log mess item', e);
    }
  };

  const currentItems = MESS_MENU[selectedMeal];

  return (
    <div className="fixed inset-0 z-[100] bg-black/50 backdrop-blur-sm flex items-end sm:items-center justify-center p-4">
      <motion.div
        initial={{ opacity: 0, y: 40 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: 40 }}
        className="bg-white rounded-[32px] w-full max-w-lg overflow-hidden shadow-2xl border border-gray-100 flex flex-col max-h-[90vh]"
      >
        {/* Header */}
        <div className="p-6 bg-gradient-to-r from-emerald-600 to-teal-700 text-white flex justify-between items-start">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-2xl bg-white/20 flex items-center justify-center text-white backdrop-blur-sm">
              <UtensilsCrossed size={24} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-xl font-black">MessOS Intelligence</h3>
                <span className="text-[10px] font-black uppercase tracking-wider bg-white/25 px-2 py-0.5 rounded-full">
                  Campus Mode
                </span>
              </div>
              <p className="text-xs text-white/80">
                Nutrient optimization for hostel & college mess dining
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

        {/* Meal Selector Tabs */}
        <div className="flex border-b border-gray-100 bg-gray-50/50 p-2 gap-1.5">
          {(['breakfast', 'lunch', 'dinner'] as const).map((meal) => (
            <button
              key={meal}
              onClick={() => {
                triggerHaptic(hapticPatterns.light);
                setSelectedMeal(meal);
              }}
              className={`flex-1 py-2.5 rounded-xl text-xs font-bold capitalize transition-all ${
                selectedMeal === meal
                  ? 'bg-white text-emerald-700 shadow-sm border border-gray-200/60'
                  : 'text-gray-500 hover:text-gray-900'
              }`}
            >
              {meal}
            </button>
          ))}
        </div>

        {/* Items List */}
        <div className="p-6 overflow-y-auto space-y-3.5 flex-1">
          <div className="p-3.5 rounded-2xl bg-amber-50/70 border border-amber-200/60 flex items-start gap-2.5">
            <Lightbulb size={18} className="text-amber-700 shrink-0 mt-0.5" />
            <p className="text-xs text-amber-900 leading-relaxed font-medium">
              <strong className="font-bold">Hostel Pro-Tip:</strong> Mess gravies contain high amounts of refined palm oil. Request dry sabzi or skim the surface layer to save 120-180 hidden calories per meal!
            </p>
          </div>

          {currentItems.map((item, idx) => (
            <div
              key={idx}
              className="p-4 rounded-2xl border border-gray-100 bg-white hover:border-emerald-200 transition-all shadow-sm space-y-2.5"
            >
              <div className="flex justify-between items-start">
                <div>
                  <div className="flex items-center gap-2">
                    <h4 className="text-sm font-bold text-gray-900">{item.name}</h4>
                    <span className="text-[10px] font-bold text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-100">
                      {item.tag}
                    </span>
                  </div>
                  <p className="text-xs text-gray-500 mt-1 italic leading-relaxed">
                    "{item.hack}"
                  </p>
                </div>
                <button
                  onClick={() => handleQuickLog(item)}
                  className="px-3 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl text-xs font-bold flex items-center gap-1 shadow-sm shrink-0 ml-2"
                >
                  <PlusCircle size={14} />
                  <span>Log</span>
                </button>
              </div>

              {/* Macros Breakdown */}
              <div className="grid grid-cols-4 gap-2 pt-2 border-t border-gray-100 text-center">
                <div className="p-1 rounded-lg bg-gray-50">
                  <span className="text-[9px] font-bold text-gray-400 uppercase block">Cal</span>
                  <span className="text-xs font-black text-gray-800">{item.calories}</span>
                </div>
                <div className="p-1 rounded-lg bg-blue-50">
                  <span className="text-[9px] font-bold text-blue-600 uppercase block">Prot</span>
                  <span className="text-xs font-black text-blue-900">{item.protein}g</span>
                </div>
                <div className="p-1 rounded-lg bg-amber-50">
                  <span className="text-[9px] font-bold text-amber-600 uppercase block">Carb</span>
                  <span className="text-xs font-black text-amber-900">{item.carbs}g</span>
                </div>
                <div className="p-1 rounded-lg bg-rose-50">
                  <span className="text-[9px] font-bold text-rose-600 uppercase block">Fat</span>
                  <span className="text-xs font-black text-rose-900">{item.fats}g</span>
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* Logged Toast */}
        <AnimatePresence>
          {loggedToast && (
            <motion.div
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 10 }}
              className="p-3 bg-emerald-600 text-white text-center text-xs font-bold flex items-center justify-center gap-1.5"
            >
              <Check size={14} strokeWidth={3} />
              <span>{loggedToast}</span>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    </div>
  );
};
