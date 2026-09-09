import { 
  UserProfile, 
  ScanResult, 
  ChatMessage, 
  DailySummary, 
  AppUser, 
  FoodMemoryItem, 
  MessMenuItem, 
  WorkoutSession 
} from '../types';

/**
 * NutriSnap AI v2.0 - Local-First On-Device Storage Engine
 * 
 * Philosophy:
 * - Free Users: All data stored on-device. Auto-purges scans & chats older than 30 days.
 * - Premium Users: Unlimited history retention + opt-in cloud sync.
 * - Zero external dependencies required for core operations.
 */

const STORAGE_KEYS = {
  ACTIVE_USER: 'nutrisnap_active_user',
  PROFILE_PREFIX: 'nutrisnap_profile_',
  SCANS_PREFIX: 'nutrisnap_scans_',
  SUMMARIES_PREFIX: 'nutrisnap_summaries_',
  CHAT_PREFIX: 'nutrisnap_chat_',
  FOOD_MEMORY_PREFIX: 'nutrisnap_food_memory_',
  MESS_MENUS_PREFIX: 'nutrisnap_mess_menus_',
  WORKOUTS_PREFIX: 'nutrisnap_workouts_',
  LAST_PURGE_PREFIX: 'nutrisnap_last_purge_',
};

const EVENT_NAME = 'nutrisnap_local_storage_updated';

function notifyStorageChange(entity: string) {
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent(EVENT_NAME, { detail: { entity } }));
  }
}

// Convert File / Blob to compressed Base64 Data URL for local private storage
export const compressImage = (fileOrDataUrl: File | Blob | string, maxWidth = 900, maxHeight = 900, quality = 0.75): Promise<string> => {
  return new Promise((resolve) => {
    if (typeof window === 'undefined') {
      resolve(typeof fileOrDataUrl === 'string' ? fileOrDataUrl : '');
      return;
    }

    const processSrc = (src: string) => {
      const img = new Image();
      img.onload = () => {
        let width = img.width;
        let height = img.height;

        if (width > maxWidth || height > maxHeight) {
          if (width > height) {
            height = Math.round((height * maxWidth) / width);
            width = maxWidth;
          } else {
            width = Math.round((width * maxHeight) / height);
            height = maxHeight;
          }
        }

        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, width);
        canvas.height = Math.max(1, height);
        const ctx = canvas.getContext('2d');
        if (ctx) {
          ctx.drawImage(img, 0, 0, width, height);
          resolve(canvas.toDataURL('image/jpeg', quality));
        } else {
          resolve(src);
        }
      };
      img.onerror = () => resolve(src);
      img.src = src;
    };

    if (typeof fileOrDataUrl === 'string') {
      if (!fileOrDataUrl) {
        resolve('');
        return;
      }
      processSrc(fileOrDataUrl);
    } else {
      const reader = new FileReader();
      reader.onload = () => {
        if (typeof reader.result === 'string') {
          processSrc(reader.result);
        } else {
          resolve('');
        }
      };
      reader.onerror = () => resolve('');
      reader.readAsDataURL(fileOrDataUrl);
    }
  });
};

export const fileToBase64 = async (file: File | Blob): Promise<string> => {
  return await compressImage(file, 900, 900, 0.75);
};

// Current active local user management
export const getActiveLocalUser = (): AppUser => {
  try {
    const stored = localStorage.getItem(STORAGE_KEYS.ACTIVE_USER);
    if (stored) {
      return JSON.parse(stored);
    }
  } catch (e) {
    console.warn('Failed to read active user from localStorage:', e);
  }
  
  // Default on-device private user
  const defaultUser: AppUser = {
    uid: 'local_user_default',
    email: 'private.user@on-device.local',
    displayName: 'NutriSnap User',
    photoURL: '',
    isGuest: false,
  };
  localStorage.setItem(STORAGE_KEYS.ACTIVE_USER, JSON.stringify(defaultUser));
  return defaultUser;
};

export const setActiveLocalUser = (user: AppUser): void => {
  localStorage.setItem(STORAGE_KEYS.ACTIVE_USER, JSON.stringify(user));
  notifyStorageChange('user');
};

// Image storage - completely on-device
export const uploadProfileImage = async (file: File): Promise<string> => {
  // Compress profile image to 400x400 with 0.7 quality to ensure reliable, high-speed local persistence without quota limits
  const dataUrl = await compressImage(file, 400, 400, 0.7);
  await saveUserProfile({ photoURL: dataUrl, localPhotoPath: dataUrl });
  const active = getActiveLocalUser();
  active.photoURL = dataUrl;
  setActiveLocalUser(active);
  notifyStorageChange('profile');
  return dataUrl;
};

export const uploadBodyImage = async (file: File): Promise<string> => {
  const dataUrl = await fileToBase64(file);
  await saveUserProfile({ bodyScanURL: dataUrl, localBodyScanPath: dataUrl });
  notifyStorageChange('profile');
  return dataUrl;
};

export const uploadScanImage = async (file: File): Promise<string> => {
  return await fileToBase64(file);
};

// User profile management
export const saveUserProfile = async (profileUpdate: Partial<UserProfile>): Promise<void> => {
  const user = getActiveLocalUser();
  const uid = profileUpdate.uid || user.uid;
  const key = `${STORAGE_KEYS.PROFILE_PREFIX}${uid}`;
  
  let existingProfile: Partial<UserProfile> = {};
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      existingProfile = JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error reading profile:', e);
  }

  let bodyScanURL = profileUpdate.bodyScanURL !== undefined ? profileUpdate.bodyScanURL : existingProfile.bodyScanURL;
  let localBodyScanPath = profileUpdate.localBodyScanPath !== undefined ? profileUpdate.localBodyScanPath : existingProfile.localBodyScanPath;
  if (profileUpdate.bodyScanURL && !profileUpdate.localBodyScanPath) {
    localBodyScanPath = profileUpdate.bodyScanURL;
  } else if (profileUpdate.localBodyScanPath && !profileUpdate.bodyScanURL) {
    bodyScanURL = profileUpdate.localBodyScanPath;
  }

  const mergedProfile: UserProfile = {
    uid,
    email: profileUpdate.email || existingProfile.email || user.email,
    displayName: profileUpdate.displayName || existingProfile.displayName || user.displayName,
    photoURL: profileUpdate.photoURL !== undefined ? profileUpdate.photoURL : existingProfile.photoURL,
    localPhotoPath: profileUpdate.localPhotoPath !== undefined ? profileUpdate.localPhotoPath : existingProfile.localPhotoPath,
    height: profileUpdate.height ?? existingProfile.height ?? 175,
    weight: profileUpdate.weight ?? existingProfile.weight ?? 70,
    bmi: profileUpdate.bmi ?? existingProfile.bmi ?? 22.9,
    age: profileUpdate.age ?? existingProfile.age ?? 22,
    dob: profileUpdate.dob ?? existingProfile.dob,
    gender: profileUpdate.gender ?? existingProfile.gender ?? 'male',
    bodyType: profileUpdate.bodyType ?? existingProfile.bodyType ?? 'mesomorph',
    fatEstimate: profileUpdate.fatEstimate ?? existingProfile.fatEstimate ?? 18,
    muscleMass: profileUpdate.muscleMass ?? existingProfile.muscleMass ?? 32,
    fitnessLevel: profileUpdate.fitnessLevel ?? existingProfile.fitnessLevel ?? 'Intermediate Fit',
    bodyScanURL,
    localBodyScanPath,
    goal: profileUpdate.goal ?? existingProfile.goal ?? 'maintain',
    calorieLimit: profileUpdate.calorieLimit ?? existingProfile.calorieLimit ?? 2000,
    proteinGoal: profileUpdate.proteinGoal ?? existingProfile.proteinGoal ?? 150,
    carbsGoal: profileUpdate.carbsGoal ?? existingProfile.carbsGoal ?? 200,
    fatsGoal: profileUpdate.fatsGoal ?? existingProfile.fatsGoal ?? 67,
    proteinPct: profileUpdate.proteinPct ?? existingProfile.proteinPct ?? 30,
    carbsPct: profileUpdate.carbsPct ?? existingProfile.carbsPct ?? 45,
    fatsPct: profileUpdate.fatsPct ?? existingProfile.fatsPct ?? 25,
    waterGoal: profileUpdate.waterGoal ?? existingProfile.waterGoal ?? 2500,
    lifestyle: profileUpdate.lifestyle ?? existingProfile.lifestyle ?? 'student',
    activityLevel: profileUpdate.activityLevel ?? existingProfile.activityLevel ?? 'moderate',
    dietaryPreferences: profileUpdate.dietaryPreferences ?? existingProfile.dietaryPreferences ?? ['Vegetarian'],
    allergies: profileUpdate.allergies ?? existingProfile.allergies ?? [],
    budgetRange: profileUpdate.budgetRange ?? existingProfile.budgetRange ?? 'moderate',
    isHostelUser: profileUpdate.isHostelUser ?? existingProfile.isHostelUser ?? false,
    isPremium: profileUpdate.isPremium ?? existingProfile.isPremium ?? false,
    reminders: profileUpdate.reminders ?? existingProfile.reminders ?? [
      { id: '1', time: '08:00', type: 'meal', enabled: true },
      { id: '2', time: '13:00', type: 'meal', enabled: true },
      { id: '3', time: '20:00', type: 'meal', enabled: true },
      { id: '4', time: '10:00', type: 'water', enabled: true },
      { id: '5', time: '15:00', type: 'water', enabled: true },
    ],
    theme: profileUpdate.theme ?? existingProfile.theme ?? 'light',
    hasCompletedOnboarding: profileUpdate.hasCompletedOnboarding ?? existingProfile.hasCompletedOnboarding ?? true,
    createdAt: existingProfile.createdAt || new Date().toISOString(),
    lastLoginAt: new Date().toISOString(),
  };

  try {
    localStorage.setItem(key, JSON.stringify(mergedProfile));
  } catch (quotaErr) {
    console.warn('LocalStorage quota warning in saveUserProfile, compressing images further', quotaErr);
    if (mergedProfile.photoURL && mergedProfile.photoURL.startsWith('data:')) {
      mergedProfile.photoURL = await compressImage(mergedProfile.photoURL, 300, 300, 0.6);
      mergedProfile.localPhotoPath = mergedProfile.photoURL;
    }
    if (mergedProfile.bodyScanURL && mergedProfile.bodyScanURL.startsWith('data:')) {
      mergedProfile.bodyScanURL = await compressImage(mergedProfile.bodyScanURL, 600, 600, 0.6);
      mergedProfile.localBodyScanPath = mergedProfile.bodyScanURL;
    }
    try {
      localStorage.setItem(key, JSON.stringify(mergedProfile));
    } catch (retryErr) {
      console.error('Failed to save profile to localStorage:', retryErr);
    }
  }
  
  // If display name or photo updated, sync to active user
  if (profileUpdate.displayName || profileUpdate.photoURL) {
    setActiveLocalUser({
      ...user,
      displayName: mergedProfile.displayName || user.displayName,
      photoURL: mergedProfile.photoURL || user.photoURL,
    });
  }
  
  notifyStorageChange('profile');
};

export const getUserProfile = async (uid?: string): Promise<UserProfile | null> => {
  const user = getActiveLocalUser();
  const targetUid = uid || user.uid;
  const key = `${STORAGE_KEYS.PROFILE_PREFIX}${targetUid}`;
  
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      return JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error fetching profile:', e);
  }
  return null;
};

// ==========================================
// 30-DAY AUTO-PURGE LOGIC (Free Tier)
// ==========================================

export const purgeOldDataIfNeeded = async (): Promise<{ purgedCount: number; notice?: string }> => {
  const user = getActiveLocalUser();
  const profile = await getUserProfile(user.uid);
  
  // Premium users skip auto-purge entirely
  if (profile?.isPremium) {
    return { purgedCount: 0 };
  }

  const lastPurgeKey = `${STORAGE_KEYS.LAST_PURGE_PREFIX}${user.uid}`;
  const lastPurge = localStorage.getItem(lastPurgeKey);
  const now = new Date();
  
  // Run once per day max
  if (lastPurge && (now.getTime() - new Date(lastPurge).getTime()) < 24 * 60 * 60 * 1000) {
    return { purgedCount: 0 };
  }

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 30);
  const cutoffIso = cutoff.toISOString();

  let purgedCount = 0;

  // 1. Purge Scans older than 30 days
  const scansKey = `${STORAGE_KEYS.SCANS_PREFIX}${user.uid}`;
  try {
    const scansRaw = localStorage.getItem(scansKey);
    if (scansRaw) {
      const scans: ScanResult[] = JSON.parse(scansRaw);
      const filtered = scans.filter(s => s.timestamp >= cutoffIso);
      purgedCount += (scans.length - filtered.length);
      localStorage.setItem(scansKey, JSON.stringify(filtered));
    }
  } catch (e) {
    console.warn('Purge scans failed:', e);
  }

  // 2. Purge Chat older than 30 days
  const chatKey = `${STORAGE_KEYS.CHAT_PREFIX}${user.uid}`;
  try {
    const chatRaw = localStorage.getItem(chatKey);
    if (chatRaw) {
      const msgs: ChatMessage[] = JSON.parse(chatRaw);
      const filtered = msgs.filter(m => m.timestamp >= cutoffIso);
      purgedCount += (msgs.length - filtered.length);
      localStorage.setItem(chatKey, JSON.stringify(filtered));
    }
  } catch (e) {
    console.warn('Purge chat failed:', e);
  }

  // 3. Purge Daily summaries older than 30 days
  const summariesKey = `${STORAGE_KEYS.SUMMARIES_PREFIX}${user.uid}`;
  try {
    const sumRaw = localStorage.getItem(summariesKey);
    if (sumRaw) {
      const map: Record<string, DailySummary> = JSON.parse(sumRaw);
      const cutoffDateStr = cutoff.toISOString().split('T')[0];
      const newMap: Record<string, DailySummary> = {};
      for (const [date, val] of Object.entries(map)) {
        if (date >= cutoffDateStr) {
          newMap[date] = val;
        } else {
          purgedCount++;
        }
      }
      localStorage.setItem(summariesKey, JSON.stringify(newMap));
    }
  } catch (e) {
    console.warn('Purge summaries failed:', e);
  }

  localStorage.setItem(lastPurgeKey, now.toISOString());
  
  if (purgedCount > 0) {
    notifyStorageChange('purge');
  }

  return { 
    purgedCount, 
    notice: purgedCount > 0 ? `Cleaned ${purgedCount} historical records older than 30 days to optimize local device storage.` : undefined 
  };
};

// ==========================================
// SCANS & HISTORY
// ==========================================

export const saveScanResult = async (scan: Omit<ScanResult, 'id' | 'userId' | 'timestamp'>): Promise<ScanResult> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.SCANS_PREFIX}${user.uid}`;
  
  let existingScans: ScanResult[] = [];
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      existingScans = JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error reading scans:', e);
  }

  let finalImageUrl = scan.imageUrl || scan.localImagePath || '';
  if (finalImageUrl && finalImageUrl.startsWith('data:') && finalImageUrl.length > 200000) {
    try {
      finalImageUrl = await compressImage(finalImageUrl, 800, 800, 0.7);
    } catch {
      // fallback
    }
  }

  const finalScan: ScanResult = {
    id: `scan_${Date.now()}`,
    userId: user.uid,
    foodName: scan.foodName || 'Nutrition Log',
    type: scan.type || 'food',
    description: scan.description || '',
    details: scan.details || '',
    calories: Math.round(scan.calories || 0),
    protein: Math.round(scan.protein || 0),
    carbs: Math.round(scan.carbs || 0),
    fats: Math.round(scan.fats || 0),
    fatEstimate: scan.fatEstimate,
    confidence: scan.confidence || 0.95,
    imageUrl: finalImageUrl,
    localImagePath: finalImageUrl,
    source: scan.source || 'camera',
    isSynced: false,
    timestamp: new Date().toISOString(),
  };

  existingScans.unshift(finalScan);

  try {
    localStorage.setItem(key, JSON.stringify(existingScans));
  } catch (quotaErr) {
    console.warn('LocalStorage quota warning in saveScanResult, trimming older image payloads', quotaErr);
    // Trim raw images on scans older than the latest 5 scans
    existingScans.forEach((s, idx) => {
      if (idx >= 5 && s.imageUrl && s.imageUrl.startsWith('data:')) {
        s.imageUrl = '';
        s.localImagePath = '';
      }
    });
    try {
      localStorage.setItem(key, JSON.stringify(existingScans));
    } catch (retryErr) {
      console.error('Failed to store scans even after trimming:', retryErr);
    }
  }

  // Update Daily Summary if it has nutrition
  if (finalScan.calories > 0 || finalScan.protein > 0 || finalScan.carbs > 0 || finalScan.fats > 0) {
    await updateDailySummary(finalScan);
  }

  // Update Personal Food Twin Memory only for food logs
  if (finalScan.type === 'food') {
    await recordFoodScanInMemory(finalScan);
  }

  notifyStorageChange('scans');
  return finalScan;
};

export const getScanHistory = (callback: (scans: ScanResult[]) => void) => {
  const fetchScans = () => {
    const user = getActiveLocalUser();
    const key = `${STORAGE_KEYS.SCANS_PREFIX}${user.uid}`;
    try {
      const stored = localStorage.getItem(key);
      callback(stored ? JSON.parse(stored) : []);
    } catch (e) {
      console.error('Error reading scans:', e);
      callback([]);
    }
  };

  fetchScans();

  const listener = (event: Event) => {
    const customEvent = event as CustomEvent;
    if (customEvent.detail?.entity === 'scans' || customEvent.detail?.entity === 'all') {
      fetchScans();
    }
  };

  window.addEventListener(EVENT_NAME, listener);
  return () => window.removeEventListener(EVENT_NAME, listener);
};

export const getRecentScans = async (limitCount = 15): Promise<ScanResult[]> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.SCANS_PREFIX}${user.uid}`;
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      const scans: ScanResult[] = JSON.parse(stored);
      return scans.slice(0, limitCount);
    }
  } catch (e) {
    console.error('Error reading recent scans:', e);
  }
  return [];
};

export const deleteScan = async (scanId: string): Promise<void> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.SCANS_PREFIX}${user.uid}`;
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      const scans: ScanResult[] = JSON.parse(stored);
      const filtered = scans.filter(s => s.id !== scanId);
      localStorage.setItem(key, JSON.stringify(filtered));
      notifyStorageChange('scans');
    }
  } catch (e) {
    console.error('Error deleting scan:', e);
  }
};

// ==========================================
// DAILY SUMMARIES & WATER & STEPS
// ==========================================

const getTodayKey = (): string => {
  return new Date().toISOString().split('T')[0];
};

export const getDailySummaryOnce = async (targetDate?: string): Promise<DailySummary | null> => {
  const user = getActiveLocalUser();
  const date = targetDate || getTodayKey();
  const key = `${STORAGE_KEYS.SUMMARIES_PREFIX}${user.uid}`;
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      const map: Record<string, DailySummary> = JSON.parse(stored);
      return map[date] || {
        date,
        totalCalories: 0,
        totalProtein: 0,
        totalCarbs: 0,
        totalFats: 0,
        totalWater: 0,
        totalSteps: 4500,
        activeCalories: 180,
        sleepHours: 7.2,
      };
    }
  } catch (e) {
    console.error('Error reading summary:', e);
  }
  return {
    date,
    totalCalories: 0,
    totalProtein: 0,
    totalCarbs: 0,
    totalFats: 0,
    totalWater: 0,
    totalSteps: 4500,
    activeCalories: 180,
    sleepHours: 7.2,
  };
};

export const getDailySummary = (callback: (summary: DailySummary | null) => void) => {
  const fetchSummary = async () => {
    const summary = await getDailySummaryOnce();
    callback(summary);
  };

  fetchSummary();

  const listener = (event: Event) => {
    const customEvent = event as CustomEvent;
    if (customEvent.detail?.entity === 'summary' || customEvent.detail?.entity === 'scans' || customEvent.detail?.entity === 'all') {
      fetchSummary();
    }
  };

  window.addEventListener(EVENT_NAME, listener);
  return () => window.removeEventListener(EVENT_NAME, listener);
};

export const updateDailySummary = async (scan: ScanResult): Promise<void> => {
  const user = getActiveLocalUser();
  const date = scan.timestamp.split('T')[0] || getTodayKey();
  const key = `${STORAGE_KEYS.SUMMARIES_PREFIX}${user.uid}`;
  
  let map: Record<string, DailySummary> = {};
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      map = JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error reading summaries map:', e);
  }

  const current = map[date] || {
    date,
    totalCalories: 0,
    totalProtein: 0,
    totalCarbs: 0,
    totalFats: 0,
    totalWater: 0,
    totalSteps: 4500,
    activeCalories: 180,
    sleepHours: 7.2,
  };

  map[date] = {
    ...current,
    totalCalories: current.totalCalories + scan.calories,
    totalProtein: current.totalProtein + scan.protein,
    totalCarbs: current.totalCarbs + scan.carbs,
    totalFats: current.totalFats + scan.fats,
  };

  localStorage.setItem(key, JSON.stringify(map));
  notifyStorageChange('summary');
};

export const saveDailySummary = async (update: Partial<DailySummary>, targetDate?: string): Promise<void> => {
  const user = getActiveLocalUser();
  const date = targetDate || getTodayKey();
  const key = `${STORAGE_KEYS.SUMMARIES_PREFIX}${user.uid}`;
  let map: Record<string, DailySummary> = {};
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      map = JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error reading summaries:', e);
  }

  const current = map[date] || {
    date,
    totalCalories: 0,
    totalProtein: 0,
    totalCarbs: 0,
    totalFats: 0,
    totalWater: 0,
    totalSteps: 4500,
    activeCalories: 180,
    sleepHours: 7.2,
  };

  map[date] = {
    ...current,
    ...update,
    date,
  };

  localStorage.setItem(key, JSON.stringify(map));
  notifyStorageChange('summary');
};

export const updateWaterIntake = async (amount: number): Promise<void> => {
  const user = getActiveLocalUser();
  const date = getTodayKey();
  const key = `${STORAGE_KEYS.SUMMARIES_PREFIX}${user.uid}`;
  
  let map: Record<string, DailySummary> = {};
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      map = JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error reading summaries:', e);
  }

  const current = map[date] || {
    date,
    totalCalories: 0,
    totalProtein: 0,
    totalCarbs: 0,
    totalFats: 0,
    totalWater: 0,
    totalSteps: 4500,
    activeCalories: 180,
    sleepHours: 7.2,
  };

  map[date] = {
    ...current,
    totalWater: Math.max(0, current.totalWater + amount),
  };

  localStorage.setItem(key, JSON.stringify(map));
  notifyStorageChange('summary');
};

export const updateSteps = async (stepsDelta: number): Promise<void> => {
  const user = getActiveLocalUser();
  const date = getTodayKey();
  const key = `${STORAGE_KEYS.SUMMARIES_PREFIX}${user.uid}`;
  
  let map: Record<string, DailySummary> = {};
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      map = JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error reading summaries:', e);
  }

  const current = map[date] || {
    date,
    totalCalories: 0,
    totalProtein: 0,
    totalCarbs: 0,
    totalFats: 0,
    totalWater: 0,
    totalSteps: 4500,
    activeCalories: 180,
    sleepHours: 7.2,
  };

  const newSteps = Math.max(0, (current.totalSteps || 0) + stepsDelta);
  const activeCals = Math.round(newSteps * 0.04);

  map[date] = {
    ...current,
    totalSteps: newSteps,
    activeCalories: activeCals,
  };

  localStorage.setItem(key, JSON.stringify(map));
  notifyStorageChange('summary');
};

// ==========================================
// CHAT MESSAGES
// ==========================================

export const saveChatMessage = async (role: 'user' | 'model', text: string): Promise<ChatMessage> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.CHAT_PREFIX}${user.uid}`;
  
  let msgs: ChatMessage[] = [];
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      msgs = JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error reading chat:', e);
  }

  const newMsg: ChatMessage = {
    id: `msg_${Date.now()}`,
    userId: user.uid,
    role,
    text,
    timestamp: new Date().toISOString(),
  };

  msgs.push(newMsg);
  localStorage.setItem(key, JSON.stringify(msgs));
  notifyStorageChange('chat');
  return newMsg;
};

export const getChatHistory = (callback: (messages: ChatMessage[]) => void) => {
  const fetchChat = () => {
    const user = getActiveLocalUser();
    const key = `${STORAGE_KEYS.CHAT_PREFIX}${user.uid}`;
    try {
      const stored = localStorage.getItem(key);
      callback(stored ? JSON.parse(stored) : []);
    } catch (e) {
      console.error('Error reading chat:', e);
      callback([]);
    }
  };

  fetchChat();

  const listener = (event: Event) => {
    const customEvent = event as CustomEvent;
    if (customEvent.detail?.entity === 'chat' || customEvent.detail?.entity === 'all') {
      fetchChat();
    }
  };

  window.addEventListener(EVENT_NAME, listener);
  return () => window.removeEventListener(EVENT_NAME, listener);
};

export const clearChatHistory = async (): Promise<void> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.CHAT_PREFIX}${user.uid}`;
  localStorage.removeItem(key);
  notifyStorageChange('chat');
};

// ==========================================
// PERSONAL FOOD TWIN (Food Memory)
// ==========================================

export const getFoodMemory = async (): Promise<FoodMemoryItem[]> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.FOOD_MEMORY_PREFIX}${user.uid}`;
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      return JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error reading food memory:', e);
  }
  
  // Seed with initial intelligent dish memory
  const initialMemory: FoodMemoryItem[] = [
    {
      id: 'fm_1',
      foodName: 'Paneer Butter Masala & Roti',
      localName: 'North Indian Meal',
      category: 'Indian Curry',
      scanCount: 6,
      avgCalories: 580,
      lastEaten: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
      tags: ['Vegetarian', 'High Protein', 'Comfort Food'],
      isPreferred: true,
      confidenceScore: 0.98,
    },
    {
      id: 'fm_2',
      foodName: 'Oats with Almonds & Banana',
      localName: 'Morning Oats Bowl',
      category: 'Breakfast',
      scanCount: 12,
      avgCalories: 340,
      lastEaten: new Date().toISOString(),
      tags: ['High Fiber', 'Clean Carb', 'Quick Prep'],
      isPreferred: true,
      confidenceScore: 0.99,
    },
    {
      id: 'fm_3',
      foodName: 'Grilled Chicken Salad with Olive Oil',
      localName: 'Lean Salad',
      category: 'Salad',
      scanCount: 8,
      avgCalories: 410,
      lastEaten: new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString(),
      tags: ['Lean Protein', 'Low Carb', 'Post-Workout'],
      isPreferred: true,
      confidenceScore: 0.96,
    },
  ];
  localStorage.setItem(key, JSON.stringify(initialMemory));
  return initialMemory;
};

export const recordFoodScanInMemory = async (scan: ScanResult): Promise<void> => {
  const memory = await getFoodMemory();
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.FOOD_MEMORY_PREFIX}${user.uid}`;
  
  const existingIndex = memory.findIndex(m => m.foodName.toLowerCase() === scan.foodName.toLowerCase());
  if (existingIndex >= 0) {
    const item = memory[existingIndex];
    const newCount = item.scanCount + 1;
    const newAvg = Math.round(((item.avgCalories * item.scanCount) + scan.calories) / newCount);
    memory[existingIndex] = {
      ...item,
      scanCount: newCount,
      avgCalories: newAvg,
      lastEaten: scan.timestamp,
    };
  } else {
    memory.unshift({
      id: `fm_${Date.now()}`,
      foodName: scan.foodName,
      category: scan.type || 'Custom',
      scanCount: 1,
      avgCalories: scan.calories,
      lastEaten: scan.timestamp,
      tags: ['Scanned Meal'],
      confidenceScore: scan.confidence || 0.9,
    });
  }
  
  localStorage.setItem(key, JSON.stringify(memory));
  notifyStorageChange('food_memory');
};

// ==========================================
// MessOS — CAMPUS & HOSTEL MENU INTELLIGENCE
// ==========================================

export const getMessMenus = async (): Promise<MessMenuItem[]> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.MESS_MENUS_PREFIX}${user.uid}`;
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      return JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error reading mess menus:', e);
  }

  // Initial campus mess sample
  const today = getTodayKey();
  const defaultMenus: MessMenuItem[] = [
    {
      id: 'mess_1',
      messName: 'Campus Central Dining',
      date: today,
      mealType: 'lunch',
      items: [
        { name: 'Dal Tadka', calories: 160, protein: 9, carbs: 22, fats: 4 },
        { name: 'Jeera Rice (1 bowl)', calories: 210, protein: 4, carbs: 44, fats: 2 },
        { name: 'Aloo Gobi Subzi', calories: 140, protein: 3, carbs: 18, fats: 6 },
        { name: 'Tawa Roti (2 pcs)', calories: 150, protein: 5, carbs: 30, fats: 1 },
      ],
      createdAt: new Date().toISOString(),
    },
    {
      id: 'mess_2',
      messName: 'Campus Central Dining',
      date: today,
      mealType: 'dinner',
      items: [
        { name: 'Paneer Bhurji', calories: 240, protein: 16, carbs: 8, fats: 16 },
        { name: 'Phulka (2 pcs)', calories: 140, protein: 5, carbs: 28, fats: 1 },
        { name: 'Moong Dal Khichdi', calories: 220, protein: 8, carbs: 38, fats: 4 },
      ],
      createdAt: new Date().toISOString(),
    }
  ];
  localStorage.setItem(key, JSON.stringify(defaultMenus));
  return defaultMenus;
};

export const saveMessMenu = async (menu: Omit<MessMenuItem, 'id' | 'createdAt'>): Promise<MessMenuItem> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.MESS_MENUS_PREFIX}${user.uid}`;
  const menus = await getMessMenus();
  
  const finalMenu: MessMenuItem = {
    ...menu,
    id: `mess_${Date.now()}`,
    createdAt: new Date().toISOString(),
  };

  menus.unshift(finalMenu);
  localStorage.setItem(key, JSON.stringify(menus));
  notifyStorageChange('mess');
  return finalMenu;
};

export const deleteMessMenu = async (id: string): Promise<void> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.MESS_MENUS_PREFIX}${user.uid}`;
  const menus = await getMessMenus();
  const filtered = menus.filter(m => m.id !== id);
  localStorage.setItem(key, JSON.stringify(filtered));
  notifyStorageChange('mess');
};

// ==========================================
// WORKOUTS & HEALTH CONNECT
// ==========================================

export const getWorkoutSessions = async (): Promise<WorkoutSession[]> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.WORKOUTS_PREFIX}${user.uid}`;
  try {
    const stored = localStorage.getItem(key);
    if (stored) {
      return JSON.parse(stored);
    }
  } catch (e) {
    console.error('Error reading workouts:', e);
  }

  const today = getTodayKey();
  const defaultWorkouts: WorkoutSession[] = [
    {
      id: 'w_1',
      activityType: 'Brisk Walk',
      sourceApp: 'Health Connect',
      durationMinutes: 35,
      activeCalories: 165,
      avgHeartRate: 118,
      distanceKm: 2.8,
      sessionDate: today,
    },
    {
      id: 'w_2',
      activityType: 'Evening Gym Session',
      sourceApp: 'Fitbit',
      durationMinutes: 45,
      activeCalories: 280,
      avgHeartRate: 138,
      sessionDate: today,
    }
  ];
  localStorage.setItem(key, JSON.stringify(defaultWorkouts));
  return defaultWorkouts;
};

export const saveWorkoutSession = async (workout: Omit<WorkoutSession, 'id'>): Promise<WorkoutSession> => {
  const user = getActiveLocalUser();
  const key = `${STORAGE_KEYS.WORKOUTS_PREFIX}${user.uid}`;
  const workouts = await getWorkoutSessions();

  const finalWorkout: WorkoutSession = {
    ...workout,
    id: `workout_${Date.now()}`,
  };

  workouts.unshift(finalWorkout);
  localStorage.setItem(key, JSON.stringify(workouts));

  // Sync to daily summary active calories
  const summary = await getDailySummaryOnce(finalWorkout.sessionDate);
  if (summary) {
    const dateKey = `${STORAGE_KEYS.SUMMARIES_PREFIX}${user.uid}`;
    const stored = localStorage.getItem(dateKey);
    const map = stored ? JSON.parse(stored) : {};
    map[finalWorkout.sessionDate] = {
      ...summary,
      activeCalories: (summary.activeCalories || 0) + finalWorkout.activeCalories,
    };
    localStorage.setItem(dateKey, JSON.stringify(map));
  }

  notifyStorageChange('workouts');
  notifyStorageChange('summary');
  return finalWorkout;
};

// ==========================================
// EXPORT & RESTORE BACKUP
// ==========================================

export const exportLocalData = async (): Promise<string> => {
  const user = getActiveLocalUser();
  const profile = await getUserProfile(user.uid);
  const scansKey = `${STORAGE_KEYS.SCANS_PREFIX}${user.uid}`;
  const sumKey = `${STORAGE_KEYS.SUMMARIES_PREFIX}${user.uid}`;
  const chatKey = `${STORAGE_KEYS.CHAT_PREFIX}${user.uid}`;
  const foodMemKey = `${STORAGE_KEYS.FOOD_MEMORY_PREFIX}${user.uid}`;
  const messKey = `${STORAGE_KEYS.MESS_MENUS_PREFIX}${user.uid}`;
  const workoutsKey = `${STORAGE_KEYS.WORKOUTS_PREFIX}${user.uid}`;

  const payload = {
    version: '2.0.0-on-device',
    exportDate: new Date().toISOString(),
    user,
    profile,
    scans: localStorage.getItem(scansKey) ? JSON.parse(localStorage.getItem(scansKey)!) : [],
    summaries: localStorage.getItem(sumKey) ? JSON.parse(localStorage.getItem(sumKey)!) : {},
    chat: localStorage.getItem(chatKey) ? JSON.parse(localStorage.getItem(chatKey)!) : [],
    foodMemory: localStorage.getItem(foodMemKey) ? JSON.parse(localStorage.getItem(foodMemKey)!) : [],
    messMenus: localStorage.getItem(messKey) ? JSON.parse(localStorage.getItem(messKey)!) : [],
    workouts: localStorage.getItem(workoutsKey) ? JSON.parse(localStorage.getItem(workoutsKey)!) : [],
  };

  return JSON.stringify(payload, null, 2);
};

export const importLocalData = async (jsonString: string): Promise<boolean> => {
  try {
    const data = JSON.parse(jsonString);
    if (!data || typeof data !== 'object') return false;

    const user = getActiveLocalUser();
    const uid = data.user?.uid || user.uid;

    if (data.profile) {
      await saveUserProfile({ ...data.profile, uid });
    }
    if (data.scans && Array.isArray(data.scans)) {
      localStorage.setItem(`${STORAGE_KEYS.SCANS_PREFIX}${uid}`, JSON.stringify(data.scans));
    }
    if (data.summaries) {
      localStorage.setItem(`${STORAGE_KEYS.SUMMARIES_PREFIX}${uid}`, JSON.stringify(data.summaries));
    }
    if (data.chat && Array.isArray(data.chat)) {
      localStorage.setItem(`${STORAGE_KEYS.CHAT_PREFIX}${uid}`, JSON.stringify(data.chat));
    }
    if (data.foodMemory && Array.isArray(data.foodMemory)) {
      localStorage.setItem(`${STORAGE_KEYS.FOOD_MEMORY_PREFIX}${uid}`, JSON.stringify(data.foodMemory));
    }
    if (data.messMenus && Array.isArray(data.messMenus)) {
      localStorage.setItem(`${STORAGE_KEYS.MESS_MENUS_PREFIX}${uid}`, JSON.stringify(data.messMenus));
    }
    if (data.workouts && Array.isArray(data.workouts)) {
      localStorage.setItem(`${STORAGE_KEYS.WORKOUTS_PREFIX}${uid}`, JSON.stringify(data.workouts));
    }

    notifyStorageChange('all');
    return true;
  } catch (e) {
    console.error('Import error:', e);
    return false;
  }
};

export const clearAllLocalData = async (): Promise<void> => {
  const user = getActiveLocalUser();
  const uid = user.uid;
  localStorage.removeItem(`${STORAGE_KEYS.PROFILE_PREFIX}${uid}`);
  localStorage.removeItem(`${STORAGE_KEYS.SCANS_PREFIX}${uid}`);
  localStorage.removeItem(`${STORAGE_KEYS.SUMMARIES_PREFIX}${uid}`);
  localStorage.removeItem(`${STORAGE_KEYS.CHAT_PREFIX}${uid}`);
  localStorage.removeItem(`${STORAGE_KEYS.FOOD_MEMORY_PREFIX}${uid}`);
  localStorage.removeItem(`${STORAGE_KEYS.MESS_MENUS_PREFIX}${uid}`);
  localStorage.removeItem(`${STORAGE_KEYS.WORKOUTS_PREFIX}${uid}`);
  notifyStorageChange('all');
};
