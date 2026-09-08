import React, { useState, useEffect, useMemo, useRef } from 'react';
import { Sparkles, Plus, Check, Zap, Flame, ChevronLeft, ChevronRight, RefreshCw, Target, Wheat, Droplets } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { DailySummary, UserProfile, ScanResult } from '../types';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';
import { getPersonalizedHealthyRecommendations, PersonalizedFoodRecommendation } from '../services/geminiService';

interface HealthyFoodSuggestionsProps {
  dailySummary?: DailySummary | null;
  profile?: UserProfile | null;
  onQuickLog: (food: Omit<ScanResult, 'id' | 'userId' | 'timestamp'>) => Promise<void>;
}

// Comprehensive intelligent fallback catalog scored and sorted dynamically by user's remaining macros
const BASE_HEALTHY_FOODS: PersonalizedFoodRecommendation[] = [
  {
    id: 'food-salmon-quinoa',
    name: 'Grilled Salmon & Quinoa',
    calories: 390,
    protein: 36,
    carbs: 26,
    fats: 15,
    category: 'high_protein',
    reason: 'Rich in Omega-3s & high protein to support lean muscle recovery without blood sugar spikes.',
    matchScore: 98,
    emoji: '🐟',
    servingSize: '1 fillet + 1/2 cup quinoa',
    mealType: 'Dinner',
  },
  {
    id: 'food-avocado-toast-egg',
    name: 'Poached Egg & Avocado Toast',
    calories: 280,
    protein: 15,
    carbs: 22,
    fats: 14,
    category: 'meal',
    reason: 'Balanced monosaturated fats and quality whole egg protein for sustained mental focus.',
    matchScore: 95,
    emoji: '🥑',
    servingSize: '1 slice sourdough + 1 egg',
    mealType: 'Breakfast',
  },
  {
    id: 'food-greek-yogurt-berries',
    name: 'Greek Yogurt & Berry Medley',
    calories: 175,
    protein: 19,
    carbs: 18,
    fats: 2,
    category: 'snack',
    reason: 'Low-calorie, gut-friendly probiotics with high casein protein to curb sweet cravings.',
    matchScore: 97,
    emoji: '🫐',
    servingSize: '1 cup nonfat + fresh berries',
    mealType: 'Snack',
  },
  {
    id: 'food-mediterranean-chicken',
    name: 'Mediterranean Chicken Salad',
    calories: 330,
    protein: 38,
    carbs: 10,
    fats: 14,
    category: 'low_carb',
    reason: 'Ultra low carbohydrate footprint packed with 38g of lean breast protein and olive oil antioxidants.',
    matchScore: 96,
    emoji: '🥗',
    servingSize: '1 large bowl with greens',
    mealType: 'Lunch',
  },
  {
    id: 'food-turkey-spinach-wrap',
    name: 'Smoked Turkey & Spinach Wrap',
    calories: 310,
    protein: 32,
    carbs: 24,
    fats: 8,
    category: 'high_protein',
    reason: 'Lean poultry protein with leafy greens providing essential iron, magnesium, and potassium.',
    matchScore: 94,
    emoji: '🌯',
    servingSize: '1 whole grain wrap',
    mealType: 'Lunch',
  },
  {
    id: 'food-chia-protein-pudding',
    name: 'Almond Milk Chia Pudding',
    calories: 195,
    protein: 14,
    carbs: 15,
    fats: 9,
    category: 'snack',
    reason: 'Dense dietary fiber (8g) and hydration retention to keep you satiated throughout the afternoon.',
    matchScore: 92,
    emoji: '🥣',
    servingSize: '1 glass jar (200g)',
    mealType: 'Snack',
  },
  {
    id: 'food-tofu-edamame-bowl',
    name: 'Sesame Tofu & Edamame Bowl',
    calories: 320,
    protein: 24,
    carbs: 22,
    fats: 14,
    category: 'meal',
    reason: 'Plant-powered complete amino acid profile with antioxidant isoflavones and heart-healthy fats.',
    matchScore: 91,
    emoji: '🥢',
    servingSize: '1 bowl with steamed veg',
    mealType: 'Dinner',
  },
  {
    id: 'food-cottage-cheese-pineapple',
    name: 'Cottage Cheese & Pineapple',
    calories: 160,
    protein: 20,
    carbs: 14,
    fats: 2,
    category: 'snack',
    reason: 'Fast convenient high-protein snack loaded with calcium and bromelain enzyme for easy digestion.',
    matchScore: 93,
    emoji: '🍍',
    servingSize: '1 cup low-fat cottage cheese',
    mealType: 'Snack',
  },
];

export const HealthyFoodSuggestions: React.FC<HealthyFoodSuggestionsProps> = ({
  dailySummary,
  profile,
  onQuickLog,
}) => {
  const [selectedFilter, setSelectedFilter] = useState<'all' | 'under_budget' | 'high_protein' | 'low_carb' | 'snack'>('all');
  const [loggingId, setLoggingId] = useState<string | null>(null);
  const [loggedId, setLoggedId] = useState<string | null>(null);
  const [aiRecommendations, setAiRecommendations] = useState<PersonalizedFoodRecommendation[]>([]);
  const [isLoadingAI, setIsLoadingAI] = useState(false);
  const [hasAttemptedFetch, setHasAttemptedFetch] = useState(false);

  const scrollContainerRef = useRef<HTMLDivElement>(null);

  const consumed = dailySummary?.totalCalories || 0;
  const target = profile?.calorieLimit || 2000;
  const remainingBudget = Math.max(0, target - consumed);

  const proteinGoal = profile?.proteinGoal || 150;
  const carbsGoal = profile?.carbsGoal || 200;
  const fatsGoal = profile?.fatsGoal || 70;

  const consumedProtein = dailySummary?.totalProtein || 0;
  const consumedCarbs = dailySummary?.totalCarbs || 0;
  const consumedFats = dailySummary?.totalFats || 0;

  const remainingProtein = Math.max(0, proteinGoal - consumedProtein);

  // Fetch personalized recommendations from Gemini
  const fetchAIRecommendations = async () => {
    setIsLoadingAI(true);
    triggerHaptic(hapticPatterns.light);
    try {
      const items = await getPersonalizedHealthyRecommendations({
        remainingCalories: remainingBudget,
        calorieLimit: target,
        proteinGoal,
        carbsGoal,
        fatsGoal,
        consumedCalories: consumed,
        consumedProtein,
        consumedCarbs,
        consumedFats,
        goal: profile?.goal,
      });

      if (items && items.length > 0) {
        setAiRecommendations(items);
      }
    } catch (e) {
      console.error('Failed to fetch AI healthy food recommendations', e);
    } finally {
      setIsLoadingAI(false);
      setHasAttemptedFetch(true);
    }
  };

  // Initial fetch when user profile and calorie budget are ready
  useEffect(() => {
    if (!hasAttemptedFetch && profile) {
      fetchAIRecommendations();
    }
  }, [profile, remainingBudget]);

  // Combine AI recommendations or tailored fallback based on user's remaining calories and macro preferences
  const combinedList = useMemo(() => {
    const sourceList = aiRecommendations.length > 0 ? aiRecommendations : BASE_HEALTHY_FOODS;

    // Score items based on user's remaining macro needs & fitness goal
    return [...sourceList].sort((a, b) => {
      // If user needs high protein, boost high protein items
      if (remainingProtein > 40) {
        const proteinDiff = b.protein - a.protein;
        if (proteinDiff !== 0) return proteinDiff;
      }
      // If remaining budget is tight (<300 kcal), rank lower calorie items first
      if (remainingBudget > 0 && remainingBudget < 350) {
        return a.calories - b.calories;
      }
      return b.matchScore - a.matchScore;
    });
  }, [aiRecommendations, remainingBudget, remainingProtein]);

  // Filter recommendations based on active filter tab
  const filteredSuggestions = useMemo(() => {
    return combinedList.filter((item) => {
      if (selectedFilter === 'under_budget') {
        return remainingBudget <= 0 ? item.calories <= 200 : item.calories <= remainingBudget;
      }
      if (selectedFilter === 'high_protein') {
        return item.protein >= 20 || item.category === 'high_protein';
      }
      if (selectedFilter === 'low_carb') {
        return item.carbs <= 18 || item.category === 'low_carb';
      }
      if (selectedFilter === 'snack') {
        return item.category === 'snack' || item.mealType === 'Snack' || item.calories <= 220;
      }
      return true;
    });
  }, [combinedList, selectedFilter, remainingBudget]);

  // Horizontal scroll controls
  const scroll = (direction: 'left' | 'right') => {
    if (scrollContainerRef.current) {
      const scrollAmount = direction === 'left' ? -310 : 310;
      scrollContainerRef.current.scrollBy({ left: scrollAmount, behavior: 'smooth' });
      triggerHaptic(hapticPatterns.light);
    }
  };

  const handleLog = async (item: PersonalizedFoodRecommendation) => {
    triggerHaptic(hapticPatterns.medium);
    setLoggingId(item.id);
    try {
      await onQuickLog({
        foodName: item.name,
        type: 'food',
        calories: item.calories,
        protein: item.protein,
        carbs: item.carbs,
        fats: item.fats,
        imageUrl: `https://picsum.photos/seed/${encodeURIComponent(item.name)}/400/300`,
        confidence: 0.98,
        description: item.reason,
        details: `Serving: ${item.servingSize} • Matched for ${item.mealType}`,
      });
      setLoggedId(item.id);
      setTimeout(() => setLoggedId(null), 2500);
    } catch (e) {
      console.error('Failed to log recommended food', e);
    } finally {
      setLoggingId(null);
    }
  };

  return (
    <div id="healthy-food-recommendations-section" className="space-y-4">
      {/* Section Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 bg-emerald-50 rounded-2xl flex items-center justify-center text-emerald-600 shadow-sm border border-emerald-100">
            <Sparkles size={17} />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-base font-black text-gray-900 tracking-tight">
                Personalized Recommendations
              </h3>
              {aiRecommendations.length > 0 && (
                <span className="text-[10px] font-black uppercase tracking-wider bg-emerald-100 text-emerald-800 px-2 py-0.5 rounded-md">
                  AI Tailored
                </span>
              )}
            </div>
            <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest flex items-center gap-1.5 mt-0.5">
              <span>Target: {remainingBudget > 0 ? `${remainingBudget} kcal left` : 'Within limits'}</span>
              <span>•</span>
              <span>Needs {remainingProtein > 0 ? `${remainingProtein}g P` : 'Protein met'}</span>
            </p>
          </div>
        </div>

        {/* Action Controls: Refresh & Scroll Chevrons */}
        <div className="flex items-center gap-1.5">
          <button
            type="button"
            id="refresh-ai-recommendations-btn"
            aria-label="Refresh Recommendations"
            onClick={fetchAIRecommendations}
            disabled={isLoadingAI}
            className="w-8 h-8 rounded-full bg-white border border-gray-200 text-gray-500 hover:text-emerald-600 hover:border-emerald-200 flex items-center justify-center transition-all disabled:opacity-50"
            title="Refresh personalized recommendations"
          >
            <RefreshCw size={14} className={isLoadingAI ? 'animate-spin text-emerald-600' : ''} />
          </button>
          <button
            type="button"
            aria-label="Scroll left"
            onClick={() => scroll('left')}
            className="w-8 h-8 rounded-full bg-white border border-gray-200 text-gray-500 hover:text-gray-900 flex items-center justify-center transition-all active:scale-95"
          >
            <ChevronLeft size={16} />
          </button>
          <button
            type="button"
            aria-label="Scroll right"
            onClick={() => scroll('right')}
            className="w-8 h-8 rounded-full bg-white border border-gray-200 text-gray-500 hover:text-gray-900 flex items-center justify-center transition-all active:scale-95"
          >
            <ChevronRight size={16} />
          </button>
        </div>
      </div>

      {/* Filter Tabs */}
      <div className="flex items-center gap-2 overflow-x-auto pb-1 scrollbar-none">
        {[
          { key: 'all', label: 'All Recommendations' },
          { key: 'under_budget', label: `Under Budget (${remainingBudget} kcal)` },
          { key: 'high_protein', label: 'High Protein (20g+)' },
          { key: 'low_carb', label: 'Low Carb' },
          { key: 'snack', label: 'Light Snacks' },
        ].map((tab) => (
          <button
            key={tab.key}
            type="button"
            onClick={() => {
              triggerHaptic(hapticPatterns.light);
              setSelectedFilter(tab.key as any);
            }}
            className={`px-3.5 py-1.5 rounded-full text-xs font-bold transition-all whitespace-nowrap ${
              selectedFilter === tab.key
                ? 'bg-emerald-600 text-white shadow-sm'
                : 'bg-white border border-gray-200 text-gray-600 hover:bg-gray-50'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Horizontal Scrollable Card List */}
      <div className="relative">
        <div
          ref={scrollContainerRef}
          id="recommendations-horizontal-list"
          className="flex gap-4 overflow-x-auto pb-3 pt-1 px-1 scroll-smooth snap-x snap-mandatory scrollbar-none"
          style={{ WebkitOverflowScrolling: 'touch' }}
        >
          {filteredSuggestions.map((food) => {
            const isLogging = loggingId === food.id;
            const isLogged = loggedId === food.id;
            const fitsBudget = remainingBudget <= 0 || food.calories <= remainingBudget;
            const budgetPercent = remainingBudget > 0 ? Math.round((food.calories / remainingBudget) * 100) : 100;

            return (
              <motion.div
                key={food.id}
                layout
                initial={{ opacity: 0, scale: 0.95 }}
                animate={{ opacity: 1, scale: 1 }}
                className="w-[285px] sm:w-[310px] flex-shrink-0 snap-start glass-card p-4 rounded-3xl border border-gray-100 flex flex-col justify-between hover:border-emerald-300 hover:shadow-md transition-all group bg-white/90"
              >
                <div>
                  {/* Card Header: Emoji, Meal Type, and Match Score */}
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2.5">
                      <span className="text-3xl p-2 bg-emerald-50 rounded-2xl flex-shrink-0 shadow-inner">
                        {food.emoji}
                      </span>
                      <div>
                        <div className="flex items-center gap-1.5">
                          <span className="text-[10px] font-black uppercase tracking-wider text-emerald-800 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-100">
                            {food.mealType}
                          </span>
                          <span className="text-[10px] font-bold text-gray-400">
                            {food.servingSize}
                          </span>
                        </div>
                        <h4 className="font-bold text-gray-900 text-sm mt-1 line-clamp-1 group-hover:text-emerald-700 transition-colors">
                          {food.name}
                        </h4>
                      </div>
                    </div>

                    {/* Match Score */}
                    <div className="text-right flex-shrink-0">
                      <span className="text-[10px] font-black text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
                        {food.matchScore}% fit
                      </span>
                    </div>
                  </div>

                  {/* Calories & Remaining Budget Fit */}
                  <div className="mt-3 flex items-baseline justify-between bg-gray-50/80 px-3 py-2 rounded-2xl border border-gray-100">
                    <div className="flex items-center gap-1.5">
                      <Flame size={15} className="text-orange-500 fill-orange-500" />
                      <span className="text-lg font-black text-gray-900 tracking-tight">
                        {food.calories}
                      </span>
                      <span className="text-[10px] font-bold text-gray-400">kcal</span>
                    </div>

                    <span
                      className={`text-[10px] font-black px-2 py-0.5 rounded-full ${
                        fitsBudget
                          ? 'bg-emerald-100/80 text-emerald-800'
                          : 'bg-amber-100 text-amber-800'
                      }`}
                    >
                      {remainingBudget > 0
                        ? `${budgetPercent}% of remaining`
                        : 'Light choice'}
                    </span>
                  </div>

                  {/* Macros Badges */}
                  <div className="grid grid-cols-3 gap-1.5 mt-2.5">
                    <div className="bg-blue-50/80 border border-blue-100 rounded-xl px-2 py-1 text-center">
                      <p className="text-[9px] font-black text-blue-500 uppercase">Protein</p>
                      <p className="text-xs font-black text-blue-900">{food.protein}g</p>
                    </div>
                    <div className="bg-orange-50/80 border border-orange-100 rounded-xl px-2 py-1 text-center">
                      <p className="text-[9px] font-black text-orange-500 uppercase">Carbs</p>
                      <p className="text-xs font-black text-orange-900">{food.carbs}g</p>
                    </div>
                    <div className="bg-purple-50/80 border border-purple-100 rounded-xl px-2 py-1 text-center">
                      <p className="text-[9px] font-black text-purple-500 uppercase">Fats</p>
                      <p className="text-xs font-black text-purple-900">{food.fats}g</p>
                    </div>
                  </div>

                  {/* Personalized Rationale */}
                  <p className="text-[11px] text-gray-600 mt-2.5 line-clamp-2 leading-relaxed bg-white/70 p-2 rounded-xl border border-gray-100/60">
                    {food.reason}
                  </p>
                </div>

                {/* Quick Log Button */}
                <div className="mt-3 pt-3 border-t border-gray-100">
                  <button
                    type="button"
                    disabled={isLogging || isLogged}
                    onClick={() => handleLog(food)}
                    className={`w-full py-2.5 px-3 rounded-2xl text-xs font-black flex items-center justify-center gap-1.5 transition-all shadow-sm ${
                      isLogged
                        ? 'bg-emerald-600 text-white'
                        : isLogging
                        ? 'bg-gray-100 text-gray-400'
                        : 'bg-emerald-500 text-white hover:bg-emerald-600 active:scale-[0.98]'
                    }`}
                  >
                    {isLogged ? (
                      <>
                        <Check size={14} className="stroke-[3]" />
                        <span>Logged to Today</span>
                      </>
                    ) : isLogging ? (
                      <span className="flex items-center gap-2">
                        <span className="w-3 h-3 border-2 border-emerald-500 border-t-transparent rounded-full animate-spin" />
                        <span>Logging...</span>
                      </span>
                    ) : (
                      <>
                        <Plus size={14} className="stroke-[3]" />
                        <span>Quick Log Food</span>
                      </>
                    )}
                  </button>
                </div>
              </motion.div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
