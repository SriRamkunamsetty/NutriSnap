import { GoogleGenAI, Type } from "@google/genai";
import { ScanResult } from "../types";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY || "" });

export const analyzeFoodImage = async (base64Image: string, mimeType: string): Promise<Partial<ScanResult>> => {
  const model = "gemini-3.1-pro-preview";
  
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
            text: "Analyze this image. First, determine if it's a food item (anything edible), a person, or an animal. If it's a person, identify if it's a male or female. If it's an animal, identify the species. If it's food, provide a detailed nutritional breakdown. Return as JSON with: foodName (the name of the object), type ('food', 'person', 'animal', or 'other'), details (gender for person, species for animal, or specific food type), description (a brief summary of what you see), estimated calories, protein (g), carbs (g), fats (g), and your confidence level (0-1). IMPORTANT: If the item is edible, ALWAYS set type to 'food'. For non-food items, set nutritional values to 0.",
          },
        ],
      },
    ],
    config: {
      responseMimeType: "application/json",
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          foodName: { type: Type.STRING },
          type: { type: Type.STRING, enum: ["food", "person", "animal", "other"] },
          details: { type: Type.STRING },
          description: { type: Type.STRING },
          calories: { type: Type.NUMBER },
          protein: { type: Type.NUMBER },
          carbs: { type: Type.NUMBER },
          fats: { type: Type.NUMBER },
          confidence: { type: Type.NUMBER },
        },
        required: ["foodName", "type", "details", "description", "calories", "protein", "carbs", "fats", "confidence"],
      },
    },
  });

  try {
    const result = JSON.parse(response.text || "{}");
    return result;
  } catch (e) {
    console.error("Failed to parse Gemini response", e);
    throw new Error("Failed to analyze image");
  }
};

export const analyzeBodyImage = async (base64Image: string, mimeType: string) => {
  const model = "gemini-3.1-pro-preview";
  
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
            text: "Analyze this body image for fitness estimation. Estimate the body type (lean, normal, or obese) and provide a rough body fat percentage estimate. Return as JSON.",
          },
        ],
      },
    ],
    config: {
      responseMimeType: "application/json",
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          bodyType: { type: Type.STRING, description: "lean, normal, or obese" },
          fatEstimate: { type: Type.NUMBER, description: "Estimated body fat percentage" },
        },
        required: ["bodyType", "fatEstimate"],
      },
    },
  });

  try {
    return JSON.parse(response.text || "{}");
  } catch (e) {
    console.error("Failed to parse body analysis", e);
    return { bodyType: 'unknown', fatEstimate: 0 };
  }
};

export const getAICoachResponse = async (
  messages: { role: 'user' | 'model', text: string }[],
  userProfile: any,
  dailySummary: any,
  recentHistory: ScanResult[]
) => {
  const model = "gemini-3-flash-preview";
  
  const historySummary = recentHistory
    .slice(0, 15)
    .map(s => `- ${s.foodName}: ${s.calories}kcal, P:${s.protein}g, C:${s.carbs}g, F:${s.fats}g (${new Date(s.timestamp).toLocaleDateString()})`)
    .join("\n");

  const remainingCalories = (userProfile.calorieLimit || 2000) - (dailySummary?.totalCalories || 0);
  const waterProgress = dailySummary?.totalWater || 0;
  const waterGoal = userProfile.waterGoal || 2500;

  const systemInstruction = `You are NutriSnap AI, a world-class nutrition and fitness coach.
You have access to the user's real-time health data, meal history, and personal goals.

User Profile:
- Name: ${userProfile.displayName}
- Height: ${userProfile.height} cm
- Weight: ${userProfile.weight} kg
- BMI: ${userProfile.bmi || 'Not set'}
- Body Type: ${userProfile.bodyType || 'Unknown'}
- Goal: ${userProfile.goal}
- Daily Calorie Limit: ${userProfile.calorieLimit} kcal
- Protein Goal: ${userProfile.proteinGoal}g
- Carbs Goal: ${userProfile.carbsGoal}g
- Fats Goal: ${userProfile.fatsGoal}g
- Water Goal: ${waterGoal}ml

Today's Progress:
- Calories consumed: ${dailySummary?.totalCalories || 0} kcal (${remainingCalories > 0 ? remainingCalories + ' remaining' : Math.abs(remainingCalories) + ' over limit'})
- Protein: ${dailySummary?.totalProtein || 0}g / ${userProfile.proteinGoal}g
- Carbs: ${dailySummary?.totalCarbs || 0}g / ${userProfile.carbsGoal}g
- Fats: ${dailySummary?.totalFats || 0}g / ${userProfile.fatsGoal}g
- Water: ${waterProgress}ml / ${waterGoal}ml

Recent Meal History (Last 15 scans):
${historySummary || "No meals recorded yet."}

Your Task:
1. Provide highly personalized, data-driven advice. Reference specific numbers from their progress.
2. If they are over their calorie limit, be firm but encouraging, suggesting light activities or low-calorie meals for the rest of the day.
3. If they are behind on water or protein, give specific food/drink suggestions.
4. Use their BMI and Body Type to tailor the tone (e.g., more focus on satiety for weight loss, or nutrient density for maintenance).
5. If they ask about a specific food they just scanned, look at the history to see how it fits into their day.
6. Keep responses concise, professional, and motivating. Use markdown for clarity.
7. Provide 3 short, context-aware follow-up suggestions.

Return the response as JSON with 'text' (the advice) and 'suggestions' (array of strings).`;

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
    return { text: response.text, suggestions: [] };
  }
};

export interface PersonalizedFoodRecommendation {
  id: string;
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fats: number;
  category: 'meal' | 'snack' | 'high_protein' | 'low_carb';
  reason: string;
  matchScore: number;
  emoji: string;
  servingSize: string;
  mealType: 'Breakfast' | 'Lunch' | 'Dinner' | 'Snack';
}

export const getPersonalizedHealthyRecommendations = async (params: {
  remainingCalories: number;
  calorieLimit: number;
  proteinGoal: number;
  carbsGoal: number;
  fatsGoal: number;
  consumedCalories: number;
  consumedProtein: number;
  consumedCarbs: number;
  consumedFats: number;
  goal?: string;
}): Promise<PersonalizedFoodRecommendation[]> => {
  const model = "gemini-3-flash-preview";

  const remainingProtein = Math.max(0, params.proteinGoal - params.consumedProtein);
  const remainingCarbs = Math.max(0, params.carbsGoal - params.consumedCarbs);
  const remainingFats = Math.max(0, params.fatsGoal - params.consumedFats);

  const prompt = `Generate 6 personalized, delicious, real-world healthy food and meal recommendations for a user based on their specific nutrition metrics:
- Remaining Calorie Budget: ${params.remainingCalories > 0 ? `${params.remainingCalories} kcal left` : `Exceeded by ${Math.abs(params.remainingCalories)} kcal - prioritize very low-calorie nutrient-dense snacks under 150 kcal`}
- Daily Calorie Target: ${params.calorieLimit} kcal
- User Fitness Goal: ${params.goal || 'maintain'}
- Macro Target Goals: Protein ${params.proteinGoal}g, Carbs ${params.carbsGoal}g, Fats ${params.fatsGoal}g
- Remaining Macro Deficit Needed Today: Protein ~${remainingProtein}g, Carbs ~${remainingCarbs}g, Fats ~${remainingFats}g

Requirements:
1. Every recommendation MUST strictly respect the remaining calorie target and macro needs.
2. If remaining calories are low (< 300 kcal), recommend low-calorie satisfying snacks or light meals.
3. If remaining protein is high, recommend high-protein items.
4. Include a clear 'reason' explaining why this fits their remaining targets today (e.g., "Provides 28g lean protein with only 210 kcal to help close your protein gap").
5. Provide realistic portion sizes and accurate macro counts.
6. Provide an appropriate food emoji.
7. Categorize each item into 'meal', 'snack', 'high_protein', or 'low_carb'.
8. Assign a matchScore between 80 and 99.

Return a JSON array of objects.`;

  try {
    const response = await ai.models.generateContent({
      model,
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
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
              category: { type: Type.STRING, enum: ["meal", "snack", "high_protein", "low_carb"] },
              reason: { type: Type.STRING },
              matchScore: { type: Type.NUMBER },
              emoji: { type: Type.STRING },
              servingSize: { type: Type.STRING },
              mealType: { type: Type.STRING, enum: ["Breakfast", "Lunch", "Dinner", "Snack"] },
            },
            required: ["id", "name", "calories", "protein", "carbs", "fats", "category", "reason", "matchScore", "emoji", "servingSize", "mealType"],
          },
        },
      },
    });

    const parsed = JSON.parse(response.text || "[]");
    if (Array.isArray(parsed) && parsed.length > 0) {
      return parsed;
    }
    return [];
  } catch (error) {
    console.error("Failed to fetch AI healthy food recommendations:", error);
    return [];
  }
};
