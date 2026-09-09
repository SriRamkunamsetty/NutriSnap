import { UserProfile, ScanResult, ChatMessage, DailySummary, AppUser } from '../types';

/**
 * NutriSnap AI - 100% On-Device Private Local Storage Engine
 * Eliminates all external cloud database & storage dependencies.
 * All personal user health data, scans, water logs, and chat records
 * remain exclusively stored in on-device browser storage.
 */

const STORAGE_KEYS = {
  ACTIVE_USER: 'nutrisnap_active_user',
  PROFILE_PREFIX: 'nutrisnap_profile_',
  SCANS_PREFIX: 'nutrisnap_scans_',
  SUMMARIES_PREFIX: 'nutrisnap_summaries_',
  CHAT_PREFIX: 'nutrisnap_chat_',
};

const EVENT_NAME = 'nutrisnap_local_storage_updated';

function notifyStorageChange(entity: string) {
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new CustomEvent(EVENT_NAME, { detail: { entity } }));
  }
}

// Convert File / Blob to compressed Base64 Data URL for local private storage
export const fileToBase64 = (file: File | Blob): Promise<string> => {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.readAsDataURL(file);
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = (error) => reject(error);
  });
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
  const user = getActiveLocalUser();
  const dataUrl = await fileToBase64(file);
  await saveUserProfile({ photoURL: dataUrl });
  return dataUrl;
};

export const uploadAIAvatar = async (file: File): Promise<string> => {
  const dataUrl = await fileToBase64(file);
  await saveUserProfile({ aiAvatarURL: dataUrl });
  return dataUrl;
};

export const uploadBodyImage = async (file: File): Promise<string> => {
  const dataUrl = await fileToBase64(file);
  await saveUserProfile({ bodyScanURL: dataUrl });
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

  const updatedProfile: UserProfile = {
    uid,
    email: user.email,
    displayName: user.displayName,
    height: 175,
    weight: 70,
    bmi: 22.9,
    goal: 'maintain',
    calorieLimit: 2000,
    waterGoal: 2500,
    proteinGoal: 150,
    carbsGoal: 200,
    fatsGoal: 67,
    createdAt: new Date().toISOString(),
    ...existingProfile,
    ...profileUpdate,
    lastLoginAt: new Date().toISOString(),
  };

  localStorage.setItem(key, JSON.stringify(updatedProfile));
  notifyStorageChange('profile');
};

export const getUserProfile = async (uid: string): Promise<UserProfile | null> => {
  try {
    const key = `${STORAGE_KEYS.PROFILE_PREFIX}${uid}`;
    const stored = localStorage.getItem(key);
    if (stored) {
      return JSON.parse(stored) as UserProfile;
    }
  } catch (e) {
    console.error('Error retrieving user profile from local storage:', e);
  }
  return null;
};

// Daily summary management
const getSummariesMap = (uid: string): Record<string, DailySummary> => {
  try {
    const key = `${STORAGE_KEYS.SUMMARIES_PREFIX}${uid}`;
    const stored = localStorage.getItem(key);
    return stored ? JSON.parse(stored) : {};
  } catch (e) {
    console.error('Error parsing daily summaries:', e);
    return {};
  }
};

const saveSummariesMap = (uid: string, map: Record<string, DailySummary>): void => {
  const key = `${STORAGE_KEYS.SUMMARIES_PREFIX}${uid}`;
  localStorage.setItem(key, JSON.stringify(map));
  notifyStorageChange('daily_summary');
};

export const updateDailySummary = async (scan: Omit<ScanResult, 'id' | 'userId' | 'timestamp'>): Promise<void> => {
  const user = getActiveLocalUser();
  const date = new Date().toISOString().split('T')[0];
  const summaries = getSummariesMap(user.uid);
  
  const current = summaries[date] || {
    date,
    totalCalories: 0,
    totalProtein: 0,
    totalCarbs: 0,
    totalFats: 0,
    totalWater: 0,
  };

  summaries[date] = {
    date,
    totalCalories: Math.round((current.totalCalories || 0) + (scan.calories || 0)),
    totalProtein: Math.round((current.totalProtein || 0) + (scan.protein || 0)),
    totalCarbs: Math.round((current.totalCarbs || 0) + (scan.carbs || 0)),
    totalFats: Math.round((current.totalFats || 0) + (scan.fats || 0)),
    totalWater: current.totalWater || 0,
  };

  saveSummariesMap(user.uid, summaries);
};

export const updateWaterIntake = async (amount: number): Promise<void> => {
  const user = getActiveLocalUser();
  const date = new Date().toISOString().split('T')[0];
  const summaries = getSummariesMap(user.uid);

  const current = summaries[date] || {
    date,
    totalCalories: 0,
    totalProtein: 0,
    totalCarbs: 0,
    totalFats: 0,
    totalWater: 0,
  };

  summaries[date] = {
    ...current,
    totalWater: Math.max(0, (current.totalWater || 0) + amount),
  };

  saveSummariesMap(user.uid, summaries);
};

export const getDailySummary = (callback: (summary: DailySummary | null) => void): (() => void) => {
  const user = getActiveLocalUser();
  const date = new Date().toISOString().split('T')[0];

  const emitCurrent = () => {
    const summaries = getSummariesMap(user.uid);
    callback(summaries[date] || null);
  };

  // Immediate invoke
  emitCurrent();

  const listener = (e: Event) => {
    const customEvent = e as CustomEvent;
    if (!customEvent.detail || customEvent.detail.entity === 'daily_summary') {
      emitCurrent();
    }
  };

  window.addEventListener(EVENT_NAME, listener);
  return () => window.removeEventListener(EVENT_NAME, listener);
};

export const getDailySummaryOnce = async (): Promise<DailySummary | null> => {
  const user = getActiveLocalUser();
  const date = new Date().toISOString().split('T')[0];
  const summaries = getSummariesMap(user.uid);
  return summaries[date] || null;
};

// Scans management
const getScansList = (uid: string): ScanResult[] => {
  try {
    const key = `${STORAGE_KEYS.SCANS_PREFIX}${uid}`;
    const stored = localStorage.getItem(key);
    return stored ? JSON.parse(stored) : [];
  } catch (e) {
    console.error('Error parsing scans list:', e);
    return [];
  }
};

const saveScansList = (uid: string, scans: ScanResult[]): void => {
  const key = `${STORAGE_KEYS.SCANS_PREFIX}${uid}`;
  localStorage.setItem(key, JSON.stringify(scans));
  notifyStorageChange('scans');
};

export const saveScanResult = async (
  scan: Omit<ScanResult, 'id' | 'userId' | 'timestamp'>
): Promise<ScanResult> => {
  const user = getActiveLocalUser();
  const newScan: ScanResult = {
    ...scan,
    id: `scan_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
    userId: user.uid,
    timestamp: new Date().toISOString(),
  };

  const scans = getScansList(user.uid);
  scans.unshift(newScan);
  saveScansList(user.uid, scans);

  // Automatically update today's daily nutritional summary
  await updateDailySummary(scan);

  return newScan;
};

export const getScanHistory = (callback: (scans: ScanResult[]) => void): (() => void) => {
  const user = getActiveLocalUser();

  const emitCurrent = () => {
    const scans = getScansList(user.uid);
    callback(scans);
  };

  emitCurrent();

  const listener = (e: Event) => {
    const customEvent = e as CustomEvent;
    if (!customEvent.detail || customEvent.detail.entity === 'scans') {
      emitCurrent();
    }
  };

  window.addEventListener(EVENT_NAME, listener);
  return () => window.removeEventListener(EVENT_NAME, listener);
};

// Chat history management
const getChatList = (uid: string): ChatMessage[] => {
  try {
    const key = `${STORAGE_KEYS.CHAT_PREFIX}${uid}`;
    const stored = localStorage.getItem(key);
    return stored ? JSON.parse(stored) : [];
  } catch (e) {
    console.error('Error parsing chat messages:', e);
    return [];
  }
};

const saveChatList = (uid: string, messages: ChatMessage[]): void => {
  const key = `${STORAGE_KEYS.CHAT_PREFIX}${uid}`;
  localStorage.setItem(key, JSON.stringify(messages));
  notifyStorageChange('chat');
};

export const saveChatMessage = async (role: 'user' | 'model', text: string): Promise<ChatMessage> => {
  const user = getActiveLocalUser();
  const newMessage: ChatMessage = {
    id: `msg_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
    userId: user.uid,
    role,
    text,
    timestamp: new Date().toISOString(),
  };

  const messages = getChatList(user.uid);
  messages.push(newMessage);
  saveChatList(user.uid, messages);

  return newMessage;
};

export const getChatHistory = (callback: (messages: ChatMessage[]) => void): (() => void) => {
  const user = getActiveLocalUser();

  const emitCurrent = () => {
    const messages = getChatList(user.uid);
    callback(messages);
  };

  emitCurrent();

  const listener = (e: Event) => {
    const customEvent = e as CustomEvent;
    if (!customEvent.detail || customEvent.detail.entity === 'chat') {
      emitCurrent();
    }
  };

  window.addEventListener(EVENT_NAME, listener);
  return () => window.removeEventListener(EVENT_NAME, listener);
};

export const clearChatHistory = async (): Promise<void> => {
  const user = getActiveLocalUser();
  saveChatList(user.uid, []);
};

// Complete on-device data backup, export, and privacy controls
export const exportLocalData = (): string => {
  const user = getActiveLocalUser();
  const uid = user.uid;
  const backup = {
    version: '2.0.0-on-device',
    exportDate: new Date().toISOString(),
    user,
    profile: localStorage.getItem(`${STORAGE_KEYS.PROFILE_PREFIX}${uid}`),
    scans: localStorage.getItem(`${STORAGE_KEYS.SCANS_PREFIX}${uid}`),
    summaries: localStorage.getItem(`${STORAGE_KEYS.SUMMARIES_PREFIX}${uid}`),
    chat: localStorage.getItem(`${STORAGE_KEYS.CHAT_PREFIX}${uid}`),
  };
  return JSON.stringify(backup, null, 2);
};

export const importLocalData = (jsonString: string): boolean => {
  try {
    const data = JSON.parse(jsonString);
    if (!data.user || !data.user.uid) return false;
    const uid = data.user.uid;
    localStorage.setItem(STORAGE_KEYS.ACTIVE_USER, JSON.stringify(data.user));
    if (data.profile) localStorage.setItem(`${STORAGE_KEYS.PROFILE_PREFIX}${uid}`, data.profile);
    if (data.scans) localStorage.setItem(`${STORAGE_KEYS.SCANS_PREFIX}${uid}`, data.scans);
    if (data.summaries) localStorage.setItem(`${STORAGE_KEYS.SUMMARIES_PREFIX}${uid}`, data.summaries);
    if (data.chat) localStorage.setItem(`${STORAGE_KEYS.CHAT_PREFIX}${uid}`, data.chat);
    notifyStorageChange('all');
    return true;
  } catch (e) {
    console.error('Failed to import local backup:', e);
    return false;
  }
};

export const clearAllLocalData = (): void => {
  const user = getActiveLocalUser();
  const uid = user.uid;
  localStorage.removeItem(`${STORAGE_KEYS.PROFILE_PREFIX}${uid}`);
  localStorage.removeItem(`${STORAGE_KEYS.SCANS_PREFIX}${uid}`);
  localStorage.removeItem(`${STORAGE_KEYS.SUMMARIES_PREFIX}${uid}`);
  localStorage.removeItem(`${STORAGE_KEYS.CHAT_PREFIX}${uid}`);
  notifyStorageChange('all');
};
