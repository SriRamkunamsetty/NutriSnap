export type Goal = 'lose' | 'maintain' | 'gain';
export type BodyType = 'lean' | 'normal' | 'obese' | 'unknown';
export type Theme = 'light' | 'dark';

export interface Reminder {
  id: string;
  time: string; // HH:mm
  type: 'meal' | 'water';
  enabled: boolean;
}

export interface UserProfile {
  uid: string;
  email: string;
  displayName?: string;
  photoURL?: string;
  height?: number;
  weight?: number;
  bmi?: number;
  bodyType?: BodyType;
  fatEstimate?: number;
  bodyScanURL?: string;
  goal?: Goal;
  calorieLimit?: number;
  proteinGoal?: number;
  carbsGoal?: number;
  fatsGoal?: number;
  waterGoal?: number; // in ml
  reminders?: Reminder[];
  theme?: Theme;
  aiAvatarURL?: string;
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
  confidence: number;
  imageUrl?: string;
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
}

export interface DailyStats {
  date: string;
  calories: number;
  protein: number;
  carbs: number;
  fats: number;
  water: number;
}
