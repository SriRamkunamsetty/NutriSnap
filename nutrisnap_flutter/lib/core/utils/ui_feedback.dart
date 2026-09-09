import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

class UIFeedback {
  static void showSuccess(BuildContext context, String message) {
    HapticFeedback.lightImpact();
    _showSnackBar(
      context,
      message,
      Colors.green.shade600,
      LucideIcons.checkCircle,
    );
  }

  static void showError(BuildContext context, String message) {
    HapticFeedback.heavyImpact();
    _showSnackBar(
      context,
      message,
      Colors.red.shade600,
      LucideIcons.alertCircle,
    );
  }

  static void showInfo(BuildContext context, String message) {
    HapticFeedback.selectionClick();
    _showSnackBar(
      context,
      message,
      Colors.blue.shade600,
      LucideIcons.info,
    );
  }

  static void _showSnackBar(BuildContext context, String message, Color backgroundColor, IconData icon) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        elevation: 6,
      ),
    );
  }
}
