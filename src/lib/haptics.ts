/**
 * Utility for haptic feedback using the Web Vibration API.
 * Falls back gracefully if the API is not supported.
 */
export const triggerHaptic = (pattern: number | number[] = 10) => {
  if (typeof window !== 'undefined' && window.navigator && window.navigator.vibrate) {
    try {
      window.navigator.vibrate(pattern);
    } catch (e) {
      // Ignore vibration errors (e.g. if blocked by browser)
    }
  }
};

export const hapticPatterns = {
  light: 10,
  medium: 20,
  heavy: 40,
  success: [10, 30, 10],
  error: [50, 50, 50],
};
