import 'package:flutter/material.dart';

class NotificationDialogs {
  static Future<void> showHealthReminder(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CustomNotificationDialog(
        title: 'Time To Record Your Health !',
        subtitle: 'How are you feel today?',
        iconData: Icons.monitor_heart_outlined,
        iconColor: Colors.white,
        iconBgColor: const Color(0xFFFF5252),
        primaryButtonText: 'Open app',
        secondaryButtonText: 'Remind Later',
        onPrimaryPressed: () {
          Navigator.pop(ctx);
          // Handle Open app logic
        },
        onSecondaryPressed: () {
          Navigator.pop(ctx);
        },
      ),
    );
  }

  static Future<bool?> showAllergyAlert(BuildContext context, {required String description, String title = 'Allergy Alert'}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CustomNotificationDialog(
        title: title,
        subtitle: description,
        iconData: Icons.warning_amber_rounded,
        iconColor: Colors.white,
        iconBgColor: Colors.red,
        primaryButtonText: 'Yes',
        secondaryButtonText: 'No',
        secondaryButtonBorderColor: Colors.red.withValues(alpha: 0.5),
        secondaryButtonTextColor: Colors.red,
        onPrimaryPressed: () {
          Navigator.pop(ctx, true);
        },
        onSecondaryPressed: () {
          Navigator.pop(ctx, false);
        },
      ),
    );
  }

  static Future<bool?> showExpiredAlert(BuildContext context, {required String medName}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CustomNotificationDialog(
        title: 'Expired Medicine !',
        subtitle: 'Please STOP taking $medName immediately. It has expired.',
        iconData: Icons.warning_amber_rounded,
        iconColor: Colors.white,
        iconBgColor: Colors.red,
        primaryButtonText: 'I Understand',
        secondaryButtonText: 'Close',
        secondaryButtonBorderColor: Colors.red.withValues(alpha: 0.5),
        secondaryButtonTextColor: Colors.red,
        onPrimaryPressed: () {
          Navigator.pop(ctx, true);
        },
        onSecondaryPressed: () {
          Navigator.pop(ctx, false);
        },
      ),
    );
  }

  static Future<void> showMedicationReminder(
    BuildContext context, {
    required String medName,
    required String dosage,
    required String instruction,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CustomNotificationDialog(
        title: 'Time To Take Medicine !',
        subtitle: '', // Not used directly, using custom content instead
        customContent: Column(
          children: [
            Text(
              medName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              dosage,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              instruction,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        iconData: Icons.medication,
        iconColor: Colors.white,
        iconBgColor: const Color(0xFF00539E),
        primaryButtonText: 'I have taken',
        secondaryButtonText: 'Remind Later',
        onPrimaryPressed: () {
          Navigator.pop(ctx, true);
        },
        onSecondaryPressed: () {
          Navigator.pop(ctx, false);
        },
      ),
    );
  }
}

class CustomNotificationDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? customContent;
  final IconData iconData;
  final Color iconColor;
  final Color iconBgColor;
  final String primaryButtonText;
  final String secondaryButtonText;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSecondaryPressed;
  final Color? secondaryButtonBorderColor;
  final Color? secondaryButtonTextColor;

  const CustomNotificationDialog({
    super.key,
    required this.title,
    required this.subtitle,
    this.customContent,
    required this.iconData,
    required this.iconColor,
    required this.iconBgColor,
    required this.primaryButtonText,
    required this.secondaryButtonText,
    required this.onPrimaryPressed,
    required this.onSecondaryPressed,
    this.secondaryButtonBorderColor,
    this.secondaryButtonTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      backgroundColor: Colors.white,
      elevation: 10,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close button
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.black54),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 24),

            // Icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: iconBgColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(iconData, size: 50, color: iconColor),
            ),
            const SizedBox(height: 24),

            // Subtitle or Custom Content
            if (customContent != null)
              customContent!
            else
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            const SizedBox(height: 28),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: onPrimaryPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF51A77B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: Text(
                      primaryButtonText,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSecondaryPressed,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: secondaryButtonTextColor ?? Colors.black87,
                      side: BorderSide(color: secondaryButtonBorderColor ?? Colors.grey.shade400),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      secondaryButtonText,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
