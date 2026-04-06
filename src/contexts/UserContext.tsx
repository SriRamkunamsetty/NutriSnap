import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { auth } from '../firebase';
import { onAuthStateChanged, User } from 'firebase/auth';
import { UserProfile, ScanResult, DailySummary } from '../types';
import { getUserProfile, getScanHistory, getDailySummary, saveUserProfile } from '../services/storageService';
import { sendLocalNotification } from '../lib/notifications';

interface UserContextType {
  user: User | null;
  profile: UserProfile | null;
  scans: ScanResult[];
  dailySummary: DailySummary | null;
  loading: boolean;
  refreshProfile: () => Promise<void>;
  updateProfile: (updates: Partial<UserProfile>) => Promise<void>;
}

const UserContext = createContext<UserContextType | undefined>(undefined);

export const UserProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [scans, setScans] = useState<ScanResult[]>([]);
  const [dailySummary, setDailySummary] = useState<DailySummary | null>(null);
  const [loading, setLoading] = useState(true);

  const updateProfile = async (updates: Partial<UserProfile>) => {
    if (profile) {
      const newProfile = { ...profile, ...updates };
      await saveUserProfile(newProfile);
      setProfile(newProfile);
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

    // Check once immediately then every minute
    checkReminders();
    const interval = setInterval(checkReminders, 60000);
    return () => clearInterval(interval);
  }, [profile?.reminders]);

  const refreshProfile = async () => {
    if (user) {
      const p = await getUserProfile(user.uid);
      setProfile(p);
    }
  };

  useEffect(() => {
    const unsubscribeAuth = onAuthStateChanged(auth, async (currentUser) => {
      setUser(currentUser);
      if (currentUser) {
        // Load profile
        const p = await getUserProfile(currentUser.uid);
        if (p) {
          setProfile(p);
        } else {
          // Create initial profile if doesn't exist
          const initialProfile: UserProfile = {
            uid: currentUser.uid,
            email: currentUser.email || '',
            displayName: currentUser.displayName || 'User',
            height: 175,
            weight: 70,
            bmi: 22.9,
            goal: 'maintain',
            calorieLimit: 2000,
            createdAt: new Date().toISOString(),
            lastLoginAt: new Date().toISOString()
          };
          await saveUserProfile(initialProfile);
          setProfile(initialProfile);
        }

        // Listen to scans
        const unsubscribeScans = getScanHistory((s) => setScans(s));
        
        // Listen to daily summary
        const unsubscribeSummary = getDailySummary((sum) => setDailySummary(sum));

        setLoading(false);
        return () => {
          unsubscribeScans();
          unsubscribeSummary();
        };
      } else {
        setProfile(null);
        setScans([]);
        setDailySummary(null);
        setLoading(false);
      }
    });

    return () => unsubscribeAuth();
  }, []);

  return (
    <UserContext.Provider value={{ user, profile, scans, dailySummary, loading, refreshProfile, updateProfile }}>
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
