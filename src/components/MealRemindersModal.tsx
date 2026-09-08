import React, { useState, useEffect } from 'react';
import { BellRing, Clock, X, Send, Check } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import {
  MealReminder,
  getMealReminders,
  saveMealReminders,
  testMealReminder,
  requestNotificationPermission,
} from '../lib/notifications';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';

interface MealRemindersCardProps {
  onOpenSettings?: () => void;
}

export const MealRemindersCard: React.FC<MealRemindersCardProps> = () => {
  const [reminders, setReminders] = useState<MealReminder[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [testSentId, setTestSentId] = useState<string | null>(null);

  useEffect(() => {
    setReminders(getMealReminders());
  }, [isOpen]);

  const activeCount = reminders.filter((r) => r.enabled).length;

  const handleToggle = (id: string) => {
    triggerHaptic(hapticPatterns.light);
    const updated = reminders.map((r) => (r.id === id ? { ...r, enabled: !r.enabled } : r));
    setReminders(updated);
    saveMealReminders(updated);
  };

  const handleTimeChange = (id: string, newTime: string) => {
    const updated = reminders.map((r) => (r.id === id ? { ...r, time: newTime } : r));
    setReminders(updated);
    saveMealReminders(updated);
  };

  const handleTest = async (reminder: MealReminder) => {
    triggerHaptic(hapticPatterns.medium);
    await requestNotificationPermission();
    await testMealReminder(reminder);
    setTestSentId(reminder.id);
    setTimeout(() => setTestSentId(null), 2500);
  };

  return (
    <>
      <motion.div
        id="meal-reminders-card"
        initial={{ opacity: 0, y: 15 }}
        animate={{ opacity: 1, y: 0 }}
        onClick={() => {
          triggerHaptic(hapticPatterns.light);
          setIsOpen(true);
        }}
        className="glass-card p-6 rounded-[32px] ios-shadow border border-gray-100 cursor-pointer hover:border-amber-200 transition-all"
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-amber-500/10 rounded-2xl flex items-center justify-center text-amber-600">
              <BellRing size={20} strokeWidth={2.5} />
            </div>
            <div>
              <h3 className="font-bold text-gray-900 tracking-tight">Meal Reminders</h3>
              <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">
                {activeCount} of 3 Daily Reminders Active
              </p>
            </div>
          </div>
          <span
            className={`text-xs font-bold px-3 py-1 rounded-full ${
              activeCount > 0
                ? 'bg-green-50 text-green-700 border border-green-200'
                : 'bg-gray-100 text-gray-500'
            }`}
          >
            {activeCount > 0 ? 'Active' : 'Muted'}
          </span>
        </div>

        {/* Quick horizontal row */}
        <div className="grid grid-cols-3 gap-2 mt-4">
          {reminders.map((r) => {
            const emoji =
              r.type === 'breakfast' ? '🥐' : r.type === 'lunch' ? '🥗' : '🍲';
            return (
              <div
                key={r.id}
                className={`py-2 px-2.5 rounded-2xl text-center border transition-all ${
                  r.enabled
                    ? 'bg-green-50/50 border-green-200'
                    : 'bg-gray-50/50 border-transparent text-gray-400'
                }`}
              >
                <div className="text-base">{emoji}</div>
                <div className="text-[11px] font-bold text-gray-800">{r.label}</div>
                <div
                  className={`text-[11px] font-black ${
                    r.enabled ? 'text-green-700' : 'text-gray-400'
                  }`}
                >
                  {r.time}
                </div>
              </div>
            );
          })}
        </div>
      </motion.div>

      {/* Reminder Config Modal */}
      <AnimatePresence>
        {isOpen && (
          <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 backdrop-blur-sm p-4">
            <motion.div
              initial={{ opacity: 0, y: 50, scale: 0.95 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 50, scale: 0.95 }}
              className="bg-white w-full max-w-md rounded-[36px] p-6 space-y-6 shadow-2xl relative"
            >
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-xl font-black text-gray-900 tracking-tight">
                    Daily Meal Reminders
                  </h3>
                  <p className="text-xs text-gray-400 font-medium">
                    Recurring notifications to log your breakfast, lunch, and dinner.
                  </p>
                </div>
                <button
                  onClick={() => setIsOpen(false)}
                  className="w-9 h-9 rounded-full bg-gray-100 flex items-center justify-center text-gray-500 hover:bg-gray-200"
                >
                  <X size={18} />
                </button>
              </div>

              {/* Reminders List */}
              <div className="space-y-3">
                {reminders.map((reminder) => {
                  const emoji =
                    reminder.type === 'breakfast'
                      ? '🥐'
                      : reminder.type === 'lunch'
                      ? '🥗'
                      : '🍲';
                  return (
                    <div
                      key={reminder.id}
                      className={`p-4 rounded-2xl border transition-all ${
                        reminder.enabled
                          ? 'bg-white border-green-300 shadow-sm'
                          : 'bg-gray-50 border-gray-100 opacity-70'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-3">
                          <span className="text-2xl">{emoji}</span>
                          <div>
                            <div className="font-bold text-gray-900 text-sm">
                              {reminder.label}
                            </div>
                            <div className="text-[11px] text-gray-400">
                              {reminder.message}
                            </div>
                          </div>
                        </div>

                        {/* Switch */}
                        <label className="relative inline-flex items-center cursor-pointer">
                          <input
                            type="checkbox"
                            checked={reminder.enabled}
                            onChange={() => handleToggle(reminder.id)}
                            className="sr-only peer"
                          />
                          <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-green-600"></div>
                        </label>
                      </div>

                      {/* Time selector and test button */}
                      <div className="mt-3 pt-3 border-t border-gray-100 flex items-center justify-between">
                        <div className="flex items-center gap-2">
                          <Clock size={14} className="text-gray-400" />
                          <input
                            type="time"
                            value={reminder.time}
                            onChange={(e) =>
                              handleTimeChange(reminder.id, e.target.value)
                            }
                            className="text-sm font-bold text-gray-800 bg-gray-100 px-2 py-1 rounded-lg border border-transparent focus:border-green-500 focus:bg-white outline-none"
                          />
                        </div>

                        <button
                          type="button"
                          onClick={() => handleTest(reminder)}
                          className="text-xs font-bold text-green-700 bg-green-50 hover:bg-green-100 px-3 py-1.5 rounded-xl flex items-center gap-1.5 transition-colors"
                        >
                          {testSentId === reminder.id ? (
                            <>
                              <Check size={13} className="text-green-600" />
                              <span>Sent!</span>
                            </>
                          ) : (
                            <>
                              <Send size={12} />
                              <span>Test Alert</span>
                            </>
                          )}
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>

              <button
                type="button"
                onClick={() => setIsOpen(false)}
                className="w-full py-3.5 bg-green-600 hover:bg-green-700 text-white font-bold rounded-2xl transition-colors text-sm"
              >
                Done
              </button>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </>
  );
};
