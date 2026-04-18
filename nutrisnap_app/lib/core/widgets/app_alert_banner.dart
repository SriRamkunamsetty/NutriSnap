import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AppAlertBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const AppAlertBanner({super.key, required this.message, this.isError = true});

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red.shade600 : Colors.green.shade600;
    final bgColor = isError ? Colors.red.shade50 : Colors.green.shade50;
    final icon = isError ? LucideIcons.alertCircle : LucideIcons.checkCircle2;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          )
        ],
      ),
    );
  }
}
