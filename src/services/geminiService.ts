import { GoogleGenAI, Type } from "@google/genai";
import { ScanResult } from "../types";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY || "" });

export const analyzeFoodImage = async (base64Image: string, mimeType: string): Promise<Partial<ScanResult>> => {
  const model = "gemini-3.1-pro-preview"; // Using the requested model for image understanding
  
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
            text: "Analyze this food image. Identify the food item and provide a detailed nutritional breakdown. Include: foodName, estimated calories, protein (g), carbs (g), fats (g), and your confidence level (0-1). Be as accurate as possible for nutritional estimation.",
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
          calories: { type: Type.NUMBER },
          protein: { type: Type.NUMBER },
          carbs: { type: Type.NUMBER },
          fats: { type: Type.NUMBER },
          confidence: { type: Type.NUMBER },
        },
        required: ["foodName", "calories", "protein", "carbs", "fats", "confidence"],
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
    .slice(0, 5)
    .map(s => `- ${s.foodName}: ${s.calories}kcal`)
    .join("\n");

  const remainingCalories = (userProfile.calorieLimit || 2000) - (dailySummary?.totalCalories || 0);

  const systemInstruction = `You are a smart nutrition coach.

User Profile:
Height: ${userProfile.height} cm
Weight: ${userProfile.weight} kg
BMI: ${userProfile.bmi || 'Not set'}
Body Type: ${userProfile.bodyType || 'Unknown'}
Goal: ${userProfile.goal}
Daily Calorie Limit: ${userProfile.calorieLimit} kcal

Today's Progress:
Calories consumed: ${dailySummary?.totalCalories || 0} kcal
Remaining: ${remainingCalories} kcal
Protein: ${dailySummary?.totalProtein || 0}g
Carbs: ${dailySummary?.totalCarbs || 0}g
Fats: ${dailySummary?.totalFats || 0}g

Recent meals:
${historySummary || "No recent meals recorded."}

Instructions:
1. Give personalized advice based on the user's BMI, goals, and today's progress.
2. If calories exceeded, warn the user and suggest lighter options.
3. If protein is low relative to their goal, suggest high-protein foods.
4. If BMI is high, suggest a sustainable weight loss approach.
5. Keep responses short, practical, and encouraging. Use markdown.`;

  const chat = ai.chats.create({
    model,
    config: {
      systemInstruction,
    },
  });

  const lastMessage = messages[messages.length - 1].text;
  const response = await chat.sendMessage({ message: lastMessage });
  
  return response.text;
};
