import { GoogleGenAI, Type } from "@google/genai";
import { ScanResult, UserProfile } from "../types";

// Always initialize lazily / safely
const getAIClient = () => {
  return new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY || "" });
};

export const analyzeFoodImage = async (base64Image: string, mimeType: string): Promise<Partial<ScanResult>> => {
  const ai = getAIClient();
  const model = "gemini-3.8-flash";
  
  const response = await ai.models.generateContent({
    model,
    contents: [
      {
        parts: [
          {
            inlineData: {
              data: base64Image,
              mimeType: mimeType,
            },
          },
          {
            text: `Analyze this image with high precision.
1. Determine if it is an edible food item, a person, an animal, or something else.
2. If it is FOOD:
   - Identify the exact dish name (with regional specificity, e.g. 'Paneer Butter Masala', 'Masala Dosa', 'Chicken Biryani', 'Greek Salad', 'Oatmeal Bowl').
   - Estimate portion size, total calories, and exact macros: protein (g), carbs (g), fats (g).
   - Set type to 'food'. Provide a clear description highlighting ingredients and preparation style.
3. If it is a PERSON or ANIMAL or OBJECT:
   - Set foodName to a descriptive title.
   - Set calories, protein, carbs, fats to 0.
4. Return strict JSON matching the schema.`,
          },
        ],
      },
    ],
    config: {
      responseMimeType: "application/json",
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          foodName: { type: Type.STRING, description: "Descriptive name of the dish or subject" },
          type: { type: Type.STRING, enum: ["food", "person", "animal", "other"] },
          details: { type: Type.STRING, description: "Key ingredients or details" },
          description: { type: Type.STRING, description: "Brief visual summary and nutritional breakdown" },
          calories: { type: Type.NUMBER, description: "Total estimated calories" },
          protein: { type: Type.NUMBER, description: "Protein in grams" },
          carbs: { type: Type.NUMBER, description: "Carbohydrates in grams" },
          fats: { type: Type.NUMBER, description: "Fats in grams" },
          confidence: { type: Type.NUMBER, description: "Confidence score between 0.0 and 1.0" },
        },
        required: ["foodName", "type", "details", "description", "calories", "protein", "carbs", "fats", "confidence"],
      },
    },
  });

  try {
    const result = JSON.parse(response.text || "{}");
    if (!result.foodName || result.foodName.trim() === "") {
      result.foodName = "Fresh Meal Item";
    }
    return result;
  } catch (e) {
    console.error("Failed to parse Gemini response", e);
    throw new Error("Failed to analyze image");
  }
};

/**
 * Real Anthropometric + Gemini Vision Two-Layer Body Composition Analysis
 * Layer 1: Anthropometric formulas (Deurenberg & Boer) calculate baseline body fat % and muscle mass
 * Layer 2: Gemini Vision observes silhouette, posture, muscular definition, and generates personalized plan
 */
export const analyzeBodyImage = async (
  base64Image: string, 
  mimeType: string, 
  profile?: Partial<UserProfile>
): Promise<{
  bodyType: 'ectomorph' | 'mesomorph' | 'endomorph' | 'lean' | 'normal' | 'obese';
  fatEstimate: number;
  muscleMass: number;
  fitnessLevel: string;
  muscleObservations: string;
  weeklyPlan: string;
  nutritionAdjustments: string[];
}> => {
  const heightCm = profile?.height || 175;
  const weightKg = profile?.weight || 70;
  const age = profile?.age || 23;
  const gender = profile?.gender || 'male';
  
  // Layer 1: Anthropometric calculation
  const heightM = heightCm / 100;
  const bmi = Number((weightKg / (heightM * heightM)).toFixed(1));
  const genderFactor = gender === 'female' ? 0 : 1;
  
  // Deurenberg formula for adult body fat percentage:
  let baseFatPct = (1.20 * bmi) + (0.23 * age) - (10.8 * genderFactor) - 5.4;
  baseFatPct = Math.max(6, Math.min(50, Math.round(baseFatPct)));

  // Boer formula for lean body mass (LBM) in kg:
  let leanMassKg = 0;
  if (gender === 'female') {
    leanMassKg = (0.252 * weightKg) + (0.473 * heightCm) - 48.3;
  } else {
    leanMassKg = (0.407 * weightKg) + (0.267 * heightCm) - 19.2;
  }
  const baseMuscleMass = Math.max(20, Math.min(weightKg * 0.9, Math.round(leanMassKg)));

  // Layer 2: Gemini Vision Refinement
  try {
    const ai = getAIClient();
    const model = "gemini-3.8-flash";

    const prompt = `You are a certified sports physiologist and anthropometry expert.
You are evaluating a user's body composition photo.
User Profile Data:
- Height: ${heightCm} cm
- Weight: ${weightKg} kg
- BMI: ${bmi}
- Age: ${age}
- Biological Sex: ${gender}
- Calculated Anthropometric Baseline:
  - Estimated Body Fat: ~${baseFatPct}%
  - Estimated Lean Muscle Mass: ~${baseMuscleMass} kg

Task:
1. Calibrate the body fat percentage (typically 8%-35% for males, 14%-40% for females) based on visible abdominal/shoulder definition, vascularity, and silhouette.
2. Classify the user's primary somatotype:
   - 'ectomorph' (naturally lean, narrow frame, fast metabolism)
   - 'mesomorph' (athletic, rectangular torso, responsive muscle development)
   - 'endomorph' (solid, broader bone structure, tends to hold mass easily)
3. Determine fitness level (e.g. 'Athletic & Lean', 'Intermediate Fit', 'Active Healthy', 'Endurance Built', 'Body Recomposition Needed').
4. Provide:
   - muscleObservations (2-3 sentences on posture, core tone, and shoulder-to-waist ratio)
   - weeklyPlan (targeted workout routine: resistance training days, cardio balance)
   - nutritionAdjustments (array of exactly 3 tactical dietary recommendations, e.g. protein timing, caloric deficit/surplus, hydration)

Return strict JSON matching the schema.`;

    const response = await ai.models.generateContent({
      model,
      contents: [
        {
          parts: [
            {
              inlineData: {
                data: base64Image,
                mimeType: mimeType,
              },
            },
            { text: prompt },
          ],
        },
      ],
      config: {
        responseMimeType: "application/json",
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            bodyType: { type: Type.STRING, enum: ["ectomorph", "mesomorph", "endomorph", "lean", "normal", "obese"] },
            fatEstimate: { type: Type.NUMBER, description: "Calibrated body fat %" },
            muscleMass: { type: Type.NUMBER, description: "Estimated muscle mass in kg" },
            fitnessLevel: { type: Type.STRING },
            muscleObservations: { type: Type.STRING },
            weeklyPlan: { type: Type.STRING },
            nutritionAdjustments: {
              type: Type.ARRAY,
              items: { type: Type.STRING },
            },
          },
          required: ["bodyType", "fatEstimate", "muscleMass", "fitnessLevel", "muscleObservations", "weeklyPlan", "nutritionAdjustments"],
        },
      },
    });

    const parsed = JSON.parse(response.text || "{}");
    return {
      bodyType: parsed.bodyType || (baseFatPct < 15 ? 'ectomorph' : baseFatPct < 24 ? 'mesomorph' : 'endomorph'),
      fatEstimate: Number(parsed.fatEstimate) || baseFatPct,
      muscleMass: Number(parsed.muscleMass) || baseMuscleMass,
      fitnessLevel: parsed.fitnessLevel || 'Active Healthy',
      muscleObservations: parsed.muscleObservations || 'Well-proportioned frame with balanced upper and lower core stability.',
      weeklyPlan: parsed.weeklyPlan || '4 days strength training with progressive overload, 2 days moderate cardio.',
      nutritionAdjustments: parsed.nutritionAdjustments?.length ? parsed.nutritionAdjustments : [
        'Prioritize 1.8g protein per kg bodyweight spaced across 4 meals.',
        'Target a 300 kcal clean deficit on rest days.',
        'Maintain 3 liters of daily hydration for optimal metabolic rate.',
      ],
    };
  } catch (e) {
    console.warn("Vision body calibration fallback to anthropometric formulas", e);
    return {
      bodyType: baseFatPct < 15 ? 'ectomorph' : baseFatPct < 24 ? 'mesomorph' : 'endomorph',
      fatEstimate: baseFatPct,
      muscleMass: baseMuscleMass,
      fitnessLevel: 'Healthy Active',
      muscleObservations: `Estimated BMI of ${bmi} with anthropometric fat estimate of ${baseFatPct}%.`,
      weeklyPlan: '3x weekly full body resistance training + daily 7,000 steps.',
      nutritionAdjustments: [
        'Maintain daily protein target of 120-140g.',
        'Drink at least 2.5L water per day.',
        'Focus on whole foods with plenty of leafy vegetables.',
      ],
    };
  }
};

export const getAICoachResponse = async (
  messages: { role: 'user' | 'model', text: string }[],
  userProfile: any,
  dailySummary: any,
  recentHistory: ScanResult[]
) => {
  const ai = getAIClient();
  const model = "gemini-3.8-flash";
  
  const historySummary = recentHistory
    .slice(0, 15)
    .map(s => `- ${s.foodName}: ${s.calories}kcal, P:${s.protein}g, C:${s.carbs}g, F:${s.fats}g (${new Date(s.timestamp).toLocaleDateString()})`)
    .join("\n");

  const remainingCalories = (userProfile?.calorieLimit || 2000) - (dailySummary?.totalCalories || 0);
  const waterProgress = dailySummary?.totalWater || 0;
  const waterGoal = userProfile?.waterGoal || 2500;
  const stepsProgress = dailySummary?.totalSteps || 0;

  const systemInstruction = `You are NutriSnap AI, an elite on-device personal nutrition and health coach.
You possess real-time access to the user's localized health metrics, lifestyle habits, and food scans.
All data is stored privately on-device.

User Profile:
- Name: ${userProfile?.displayName || 'User'}
- Lifestyle: ${userProfile?.lifestyle || 'Student / Professional'} (${userProfile?.isHostelUser ? 'Hostel / Mess Eater' : 'Home / Restaurant'})
- Height: ${userProfile?.height} cm, Weight: ${userProfile?.weight} kg, BMI: ${userProfile?.bmi || '22.0'}
- Body Type: ${userProfile?.bodyType || 'mesomorph'}, Body Fat: ${userProfile?.fatEstimate || 18}%, Muscle: ${userProfile?.muscleMass || 32}kg
- Dietary Preferences: ${userProfile?.dietaryPreferences?.join(', ') || 'Flexible'}
- Allergies / Restrictions: ${userProfile?.allergies?.join(', ') || 'None'}
- Goal: ${userProfile?.goal || 'maintain'}
- Daily Calorie Target: ${userProfile?.calorieLimit || 2000} kcal
- Protein: ${userProfile?.proteinGoal || 130}g, Carbs: ${userProfile?.carbsGoal || 200}g, Fats: ${userProfile?.fatsGoal || 65}g
- Water Goal: ${waterGoal} ml

Today's Progress:
- Calories: ${dailySummary?.totalCalories || 0} / ${userProfile?.calorieLimit || 2000} kcal (${remainingCalories >= 0 ? remainingCalories + ' kcal remaining' : Math.abs(remainingCalories) + ' kcal over limit'})
- Protein: ${dailySummary?.totalProtein || 0}g / ${userProfile?.proteinGoal || 130}g
- Carbs: ${dailySummary?.totalCarbs || 0}g / ${userProfile?.carbsGoal || 200}g
- Fats: ${dailySummary?.totalFats || 0}g / ${userProfile?.fatsGoal || 65}g
- Water: ${waterProgress} ml / ${waterGoal} ml
- Steps: ${stepsProgress} steps today

Recent Food Logs (Last 15):
${historySummary || "No meals logged yet."}

Core Directives:
1. Offer direct, actionable, compassionate coaching. Always quote their real numbers.
2. If they are a hostel/mess user, give practical hacks for mess food (e.g., doubling dal, opting for roasted over deep-fried, paneer hacks).
3. If they are close to or over their calorie limit, suggest filling low-cal options (e.g. cucumber, buttermilk, clear broth) or an evening stroll.
4. Keep the tone friendly, smart, and motivating. Use Markdown formatting.
5. Provide 3 short, intelligent follow-up prompt suggestions for the user to tap.`;

  const response = await ai.models.generateContent({
    model,
    contents: messages.map(m => ({ role: m.role, parts: [{ text: m.text }] })),
    config: {
      systemInstruction,
      responseMimeType: "application/json",
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          text: { type: Type.STRING },
          suggestions: {
            type: Type.ARRAY,
            items: { type: Type.STRING }
          }
        },
        required: ["text", "suggestions"]
      }
    },
  });
  
  try {
    return JSON.parse(response.text || "{}");
  } catch (e) {
    console.error("Failed to parse coach response", e);
    return { text: response.text || "I'm here to support your nutrition journey. How are you feeling today?", suggestions: ["How can I hit my protein goal today?", "What should I eat for dinner?", "Give me a quick hydration tip"] };
  }
};

export interface PersonalizedFoodRecommendation {
  id: string;
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fats: number;
  reason: string;
  category: 'breakfast' | 'lunch' | 'dinner' | 'snack' | 'high_protein' | 'low_carb' | 'meal';
  isMessFriendly?: boolean;
  matchScore?: number;
  emoji?: string;
  servingSize?: string;
  mealType?: string;
}

export const getPersonalizedRecommendations = async (
  profileOrParams: any,
  dailySummary?: any,
  foodMemory?: any[]
): Promise<PersonalizedFoodRecommendation[]> => {
  const profile = (profileOrParams && 'remainingCalories' in profileOrParams)
    ? {
        calorieLimit: profileOrParams.calorieLimit,
        proteinGoal: profileOrParams.proteinGoal,
        goal: profileOrParams.goal,
        dietaryPreferences: profileOrParams.dietaryPreferences,
        isHostelUser: profileOrParams.isHostelUser,
      }
    : profileOrParams;

  const summary = dailySummary || {
    totalCalories: profileOrParams?.consumedCalories || 0,
    totalProtein: profileOrParams?.consumedProtein || 0,
    totalCarbs: profileOrParams?.consumedCarbs || 0,
    totalFats: profileOrParams?.consumedFats || 0,
  };

  const remainingCalories = Math.max(0, (profile?.calorieLimit || 2000) - (summary?.totalCalories || 0));
  const remainingProtein = Math.max(0, (profile?.proteinGoal || 130) - (summary?.totalProtein || 0));
  const isHostel = profile?.isHostelUser ?? false;

  try {
    const ai = getAIClient();
    const model = "gemini-3.8-flash";

    const prompt = `Recommend 3 smart, delicious meal options for this user.
User profile:
- Goal: ${profile?.goal || 'maintain'}
- Dietary Preferences: ${profile?.dietaryPreferences?.join(', ') || 'Vegetarian'}
- Hostel / Mess User: ${isHostel ? 'Yes' : 'No'}
- Remaining Calories for today: ${remainingCalories} kcal
- Remaining Protein needed: ${remainingProtein} g

Provide 3 recommendations balancing their macros.
Return JSON array with id, name, calories, protein, carbs, fats, reason, category (breakfast/lunch/dinner/snack), and isMessFriendly (boolean).`;

    const response = await ai.models.generateContent({
      model,
      contents: [{ parts: [{ text: prompt }] }],
      config: {
        responseMimeType: "application/json",
        responseSchema: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              id: { type: Type.STRING },
              name: { type: Type.STRING },
              calories: { type: Type.NUMBER },
              protein: { type: Type.NUMBER },
              carbs: { type: Type.NUMBER },
              fats: { type: Type.NUMBER },
              reason: { type: Type.STRING },
              category: { type: Type.STRING, enum: ["breakfast", "lunch", "dinner", "snack"] },
              isMessFriendly: { type: Type.BOOLEAN },
            },
            required: ["id", "name", "calories", "protein", "carbs", "fats", "reason", "category", "isMessFriendly"],
          },
        },
      },
    });

    return JSON.parse(response.text || "[]");
  } catch (e) {
    console.warn("Fallback food recommendations", e);
    return [
      {
        id: "rec_1",
        name: "Paneer & Sprouts Salad",
        calories: 280,
        protein: 22,
        carbs: 18,
        fats: 12,
        reason: "Rich in clean plant protein with fiber to hit daily targets without excess carbs.",
        category: "dinner",
        isMessFriendly: true,
      },
      {
        id: "rec_2",
        name: "Roasted Chana & Almond Bowl",
        calories: 190,
        protein: 9,
        carbs: 22,
        fats: 7,
        reason: "Low glycemic snack ideal for sustained focus and hunger control.",
        category: "snack",
        isMessFriendly: true,
      },
      {
        id: "rec_3",
        name: "Curd with Chia Seeds & Fresh Fruits",
        calories: 220,
        protein: 11,
        carbs: 28,
        fats: 6,
        reason: "Probiotic-rich digestion support with essential micronutrients.",
        category: "breakfast",
        isMessFriendly: true,
      },
    ];
  }
};

export const getPersonalizedHealthyRecommendations = getPersonalizedRecommendations;
