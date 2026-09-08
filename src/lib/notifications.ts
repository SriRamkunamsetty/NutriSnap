/**
 * Utility for browser-based local notifications.
 * Handles permission requests, recurring meal reminders, and sending notifications.
 */

export interface MealReminder {
  id: string;
  type: 'breakfast' | 'lunch' | 'dinner';
  label: string;
  time: string; // HH:mm (24-hour)
  enabled: boolean;
  message: string;
}

export const DEFAULT_MEAL_REMINDERS: MealReminder[] = [
  {
    id: 'breakfast',
    type: 'breakfast',
    label: 'Breakfast',
    time: '08:30',
    enabled: true,
    message: 'Time to fuel up! Log your morning meal to jumpstart your day.'
  },
  {
    id: 'lunch',
    type: 'lunch',
    label: 'Lunch',
    time: '13:00',
    enabled: true,
    message: 'Midday nutrition check! Log your lunch to stay energized.'
  },
  {
    id: 'dinner',
    type: 'dinner',
    label: 'Dinner',
    time: '19:30',
    enabled: true,
    message: 'Wrap up your daily fuel! Log your dinner to complete your macros.'
  }
];

const REMINDERS_KEY = 'nutrisnap_meal_reminders';
const LAST_NOTIFIED_KEY = 'nutrisnap_last_reminders_notified';

export const getMealReminders = (): MealReminder[] => {
  try {
    const raw = localStorage.getItem(REMINDERS_KEY);
    if (!raw) return DEFAULT_MEAL_REMINDERS;
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed) || parsed.length === 0) return DEFAULT_MEAL_REMINDERS;
    return parsed;
  } catch {
    return DEFAULT_MEAL_REMINDERS;
  }
};

export const saveMealReminders = (reminders: MealReminder[]): void => {
  try {
    localStorage.setItem(REMINDERS_KEY, JSON.stringify(reminders));
  } catch (e) {
    console.error('Failed to save meal reminders', e);
  }
};

export const requestNotificationPermission = async (): Promise<boolean> => {
  if (!("Notification" in window)) {
    console.warn("This browser does not support desktop notification");
    return false;
  }

  if (Notification.permission === "granted") {
    return true;
  }

  if (Notification.permission !== "denied") {
    try {
      const permission = await Notification.requestPermission();
      return permission === "granted";
    } catch {
      return false;
    }
  }

  return false;
};

export const sendLocalNotification = (title: string, options?: NotificationOptions) => {
  if (!("Notification" in window) || Notification.permission !== "granted") {
    return;
  }

  try {
    new Notification(title, {
      icon: "/favicon.ico",
      ...options,
    });
  } catch (e) {
    console.error("Failed to send notification", e);
  }
};

export const testMealReminder = async (reminder: MealReminder): Promise<boolean> => {
  const granted = await requestNotificationPermission();
  if (granted) {
    sendLocalNotification(`NutriSnap AI: ${reminder.label} Reminder (${reminder.time})`, {
      body: reminder.message,
      tag: `reminder-${reminder.id}`,
    });
    return true;
  }
  return false;
};

// Scheduler for periodic checks in active web sessions
let schedulerInterval: number | null = null;

export const startMealReminderScheduler = (onTrigger?: (reminder: MealReminder) => void) => {
  if (schedulerInterval !== null) return;

  const checkDue = () => {
    const reminders = getMealReminders();
    const now = new Date();
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const currentTime = `${hours}:${minutes}`;
    const today = now.toISOString().split('T')[0];

    let lastNotified: Record<string, string> = {};
    try {
      lastNotified = JSON.parse(localStorage.getItem(LAST_NOTIFIED_KEY) || '{}');
    } catch {
      lastNotified = {};
    }

    reminders.forEach((r) => {
      if (!r.enabled) return;
      const key = `${today}-${r.id}-${r.time}`;
      if (r.time === currentTime && lastNotified[r.id] !== key) {
        lastNotified[r.id] = key;
        localStorage.setItem(LAST_NOTIFIED_KEY, JSON.stringify(lastNotified));
        
        sendLocalNotification(`NutriSnap AI: Time for ${r.label}!`, {
          body: r.message,
          tag: `meal-${r.id}`,
        });
        
        if (onTrigger) onTrigger(r);
      }
    });
  };

  // Run initial check
  checkDue();
  // Check every 30 seconds
  schedulerInterval = window.setInterval(checkDue, 30000);
};

export const stopMealReminderScheduler = () => {
  if (schedulerInterval !== null) {
    clearInterval(schedulerInterval);
    schedulerInterval = null;
  }
};
