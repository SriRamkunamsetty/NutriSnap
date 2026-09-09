import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { UserProfile, ScanResult, DailySummary, AppUser } from '../types';
import { 
  getUserProfile, 
  getScanHistory, 
  getDailySummary, 
  saveUserProfile, 
  getActiveLocalUser, 
  setActiveLocalUser,
  clearAllLocalData
} from '../services/storageService';
import { sendLocalNotification } from '../lib/notifications';

interface UserContextType {
  user: AppUser | null;
  profile: UserProfile | null;
  scans: ScanResult[];
  dailySummary: DailySummary | null;
  loading: boolean;
  refreshProfile: () => Promise<UserProfile | null>;
  updateProfile: (updates: Partial<UserProfile>) => Promise<void>;
  logout: () => void;
  login: (userData: AppUser) => void;
  clearUserData: () => void;
}

const UserContext = createContext<UserContextType | undefined>(undefined);

export const UserProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<AppUser | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [scans, setScans] = useState<ScanResult[]>([]);
  const [dailySummary, setDailySummary] = useState<DailySummary | null>(null);
  const [loading, setLoading] = useState(true);

  const updateProfile = async (updates: Partial<UserProfile>) => {
    if (profile) {
      const newProfile = { ...profile, ...updates };
      setProfile(newProfile);
      try {
        await saveUserProfile(newProfile);
      } catch (error) {
        console.error("Failed to save profile updates to local storage:", error);
      }
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
    // Reset to clean local user or sign-out state
    const cleanUser: AppUser = {
      uid: `local_user_${Date.now()}`,
      email: 'private.user@on-device.local',
      displayName: 'NutriSnap User',
      photoURL: '',
    };
    setActiveLocalUser(cleanUser);
    setUser(cleanUser);
  };

  const login = (userData: AppUser) => {
    setActiveLocalUser(userData);
    setUser(userData);
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
      let p = await getUserProfile(activeUser.uid);
      if (!p) {
        const initialProfile: UserProfile = {
          uid: activeUser.uid,
          email: activeUser.email,
          displayName: activeUser.displayName,
          photoURL: activeUser.photoURL || '',
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

      setLoading(false);

      return () => {
        unsubscribeScans();
        unsubscribeSummary();
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
      refreshProfile, 
      updateProfile,
      logout,
      login,
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
