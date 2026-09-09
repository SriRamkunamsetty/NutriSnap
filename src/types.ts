export type Goal = 'lose' | 'maintain' | 'gain' | 'endurance';
export type BodyType = 'ectomorph' | 'mesomorph' | 'endomorph' | 'lean' | 'normal' | 'obese' | 'unknown';
export type Theme = 'light' | 'dark';
export type Gender = 'male' | 'female' | 'non-binary' | 'prefer-not-to-say';
export type Lifestyle = 'student' | 'professional' | 'athlete';
export type ActivityLevel = 'sedentary' | 'lightly_active' | 'moderate' | 'very_active';

export interface Reminder {
  id: string;
  time: string; // HH:mm
  type: 'meal' | 'water';
  enabled: boolean;
}

export interface AppUser {
  uid: string;
  email: string;
  displayName: string;
  photoURL?: string;
  isGuest?: boolean;
}

export interface UserProfile {
  uid: string;
  email: string;
  displayName?: string;
  photoURL?: string;
  localPhotoPath?: string;
  height?: number; // cm
  weight?: number; // kg
  bmi?: number;
  age?: number;
  dob?: string;
  gender?: Gender;
  bodyType?: BodyType;
  fatEstimate?: number;
  muscleMass?: number;
  fitnessLevel?: string;
  bodyScanURL?: string;
  localBodyScanPath?: string;
  goal?: Goal;
  calorieLimit?: number;
  proteinGoal?: number;
  carbsGoal?: number;
  fatsGoal?: number;
  proteinPct?: number;
  carbsPct?: number;
  fatsPct?: number;
  waterGoal?: number; // in ml
  lifestyle?: Lifestyle;
  activityLevel?: ActivityLevel;
  dietaryPreferences?: string[];
  allergies?: string[];
  budgetRange?: string;
  isHostelUser?: boolean;
  isPremium?: boolean;
  reminders?: Reminder[];
  theme?: Theme;
  hasCompletedOnboarding?: boolean;
  createdAt: string;
  lastLoginAt?: string;
}

export interface ScanResult {
  id: string;
  userId: string;
  foodName: string;
  type?: 'food' | 'person' | 'animal' | 'other';
  description?: string;
  details?: string;
  calories: number;
  protein: number;
  carbs: number;
  fats: number;
  fatEstimate?: number;
  confidence: number;
  imageUrl?: string;
  localImagePath?: string;
  source?: 'camera' | 'gallery' | 'manual' | 'mess';
  isSynced?: boolean;
  timestamp: string;
}

export interface ChatMessage {
  id: string;
  userId: string;
  role: 'user' | 'model';
  text: string;
  timestamp: string;
}

export interface DailySummary {
  date: string;
  totalCalories: number;
  totalProtein: number;
  totalCarbs: number;
  totalFats: number;
  totalWater: number; // in ml
  totalSteps?: number;
  activeCalories?: number;
  sleepHours?: number;
}

export interface DailyStats {
  date: string;
  calories: number;
  protein: number;
  carbs: number;
  fats: number;
  water: number;
  steps?: number;
  activeCalories?: number;
}

export interface FoodMemoryItem {
  id: string;
  foodName: string;
  localName?: string;
  category: string;
  scanCount: number;
  avgCalories: number;
  lastEaten: string;
  tags: string[];
  isAllergy?: boolean;
  isPreferred?: boolean;
  confidenceScore: number;
}

export interface MessMenuItem {
  id: string;
  messName: string;
  date: string;
  mealType: 'breakfast' | 'lunch' | 'dinner' | 'snack';
  items: {
    name: string;
    calories: number;
    protein: number;
    carbs: number;
    fats: number;
  }[];
  createdAt: string;
}

export interface WorkoutSession {
  id: string;
  activityType: string;
  sourceApp: string;
  durationMinutes: number;
  activeCalories: number;
  avgHeartRate?: number;
  distanceKm?: number;
  sessionDate: string;
}
