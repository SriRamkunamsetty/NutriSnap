import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { UserProfile, ScanResult, DailySummary, AppUser } from '../types';
import { 
  getUserProfile, 
  getScanHistory, 
  getDailySummary, 
  saveUserProfile, 
  getActiveLocalUser, 
  setActiveLocalUser,
  clearAllLocalData,
  purgeOldDataIfNeeded
} from '../services/storageService';
import { sendLocalNotification } from '../lib/notifications';

interface UserContextType {
  user: AppUser | null;
  profile: UserProfile | null;
  scans: ScanResult[];
  dailySummary: DailySummary | null;
  loading: boolean;
  purgeNotice: string | null;
  refreshProfile: () => Promise<UserProfile | null>;
  updateProfile: (updates: Partial<UserProfile>) => Promise<void>;
  logout: () => void;
  login: (userData: AppUser) => void;
  signInAsGuest: () => void;
  clearUserData: () => void;
}

const UserContext = createContext<UserContextType | undefined>(undefined);

export const UserProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<AppUser | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [scans, setScans] = useState<ScanResult[]>([]);
  const [dailySummary, setDailySummary] = useState<DailySummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [purgeNotice, setPurgeNotice] = useState<string | null>(null);

  const updateProfile = async (updates: Partial<UserProfile>) => {
    const activeUser = user || getActiveLocalUser();
    const existing = profile || (await getUserProfile(activeUser.uid)) || ({} as UserProfile);
    const newProfile = { ...existing, ...updates };
    setProfile(newProfile);
    try {
      await saveUserProfile(newProfile);
      const fresh = await getUserProfile(activeUser.uid);
      if (fresh) {
        setProfile(fresh);
      }
    } catch (error) {
      console.error("Failed to save profile updates to local storage:", error);
    }
  };

  // Reminder scheduler
  useEffect(() => {
    if (!profile?.reminders || profile.reminders.length === 0) return;

    const checkReminders = () => {
      const now = new Date();
      const currentTime = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`;
      
      profile.reminders?.forEach(reminder => {
        if (reminder.enabled && reminder.time === currentTime) {
          sendLocalNotification(
            reminder.type === 'meal' ? '🍽️ Time for a meal!' : '💧 Time to hydrate!',
            { body: `Don't forget to log your ${reminder.type} in NutriSnap.` }
          );
        }
      });
    };

    checkReminders();
    const interval = setInterval(checkReminders, 60000);
    return () => clearInterval(interval);
  }, [profile?.reminders]);

  const refreshProfile = async (): Promise<UserProfile | null> => {
    if (user) {
      const p = await getUserProfile(user.uid);
      if (p) setProfile(p);
      return p;
    }
    return null;
  };

  const logout = () => {
    const guestUser: AppUser = {
      uid: `guest_${Date.now()}`,
      email: 'guest@nutrisnap.local',
      displayName: 'Guest User',
      photoURL: '',
      isGuest: true,
    };
    setActiveLocalUser(guestUser);
    setUser(guestUser);
  };

  const signInAsGuest = () => {
    const guestUser: AppUser = {
      uid: `guest_${Date.now()}`,
      email: 'guest@nutrisnap.local',
      displayName: 'Guest User',
      photoURL: '',
      isGuest: true,
    };
    setActiveLocalUser(guestUser);
    setUser(guestUser);
  };

  const login = (userData: AppUser) => {
    const active = { ...userData, isGuest: false };
    setActiveLocalUser(active);
    setUser(active);
  };

  const clearUserData = () => {
    clearAllLocalData();
    if (user) {
      refreshProfile();
    }
  };

  // Initialize on-device active user & profile
  useEffect(() => {
    const activeUser = getActiveLocalUser();
    setUser(activeUser);

    const initUserData = async () => {
      // Run 30-day auto-purge on startup
      const purgeResult = await purgeOldDataIfNeeded();
      if (purgeResult.notice) {
        setPurgeNotice(purgeResult.notice);
      }

      let p = await getUserProfile(activeUser.uid);
      if (!p) {
        const initialProfile: UserProfile = {
          uid: activeUser.uid,
          email: activeUser.email,
          displayName: activeUser.displayName,
          photoURL: activeUser.photoURL || '',
          localPhotoPath: activeUser.photoURL || '',
          height: 175,
          weight: 70,
          bmi: 22.9,
          age: 22,
          gender: 'male',
          bodyType: 'mesomorph',
          fatEstimate: 18,
          muscleMass: 32,
          fitnessLevel: 'Intermediate Fit',
          lifestyle: 'student',
          activityLevel: 'moderate',
          dietaryPreferences: ['Vegetarian'],
          allergies: [],
          budgetRange: 'moderate',
          isHostelUser: true,
          isPremium: false,
          goal: 'maintain',
          calorieLimit: 2000,
          waterGoal: 2500,
          proteinGoal: 140,
          carbsGoal: 210,
          fatsGoal: 65,
          hasCompletedOnboarding: true,
          createdAt: new Date().toISOString(),
          lastLoginAt: new Date().toISOString(),
        };
        await saveUserProfile(initialProfile);
        p = initialProfile;
      }

      setProfile(p);

      // Listen to local scans updates
      const unsubscribeScans = getScanHistory((s) => setScans(s));

      // Listen to daily summary updates
      const unsubscribeSummary = getDailySummary((sum) => setDailySummary(sum));

      // Listen to profile updates from any screen or modal
      const handleStorageUpdate = (event: Event) => {
        const customEvent = event as CustomEvent;
        if (customEvent.detail?.entity === 'profile' || customEvent.detail?.entity === 'all') {
          getUserProfile(activeUser.uid).then((fresh) => {
            if (fresh) setProfile(fresh);
          });
        }
      };
      window.addEventListener('nutrisnap_local_storage_updated', handleStorageUpdate);

      setLoading(false);

      return () => {
        unsubscribeScans();
        unsubscribeSummary();
        window.removeEventListener('nutrisnap_local_storage_updated', handleStorageUpdate);
      };
    };

    initUserData();
  }, [user?.uid]);

  return (
    <UserContext.Provider value={{ 
      user, 
      profile, 
      scans, 
      dailySummary, 
      loading, 
      purgeNotice,
      refreshProfile, 
      updateProfile,
      logout,
      login,
      signInAsGuest,
      clearUserData
    }}>
      {children}
    </UserContext.Provider>
  );
};

export const useUser = () => {
  const context = useContext(UserContext);
  if (context === undefined) {
    throw new Error('useUser must be used within a UserProvider');
  }
  return context;
};
