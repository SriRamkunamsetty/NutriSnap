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
