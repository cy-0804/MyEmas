import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/medication_dose.dart';
import '../services/reminder_scheduler.dart';

class FsmReminderDialog extends StatelessWidget {
  final MedicationDose dose;
  final ReminderScheduler scheduler;

  const FsmReminderDialog({
    super.key,
    required this.dose,
    required this.scheduler,
  });

  static Future<void> show(
    BuildContext context,
    MedicationDose dose,
    ReminderScheduler scheduler,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => FsmReminderDialog(dose: dose, scheduler: scheduler),
    );
  }

  Widget _buildPhoto() {
    if (dose.photo == null || dose.photo!.isEmpty) {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF00539E),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(
          Icons.medication_rounded,
          size: 68,
          color: Colors.white,
        ),
      );
    }

    if (dose.photo!.startsWith('data:image')) {
      final base64Str = dose.photo!.split(',').last;
      return ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Image.memory(
          base64Decode(base64Str),
          width: 120,
          height: 120,
          fit: BoxFit.cover,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Image.network(
        dose.photo!,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Time To Take Medicine!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            _buildPhoto(),

            const SizedBox(height: 24),
            Text(
              dose.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              dose.dosage ?? 'Take as directed',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            Text(
              dose.instruction ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),

            const SizedBox(height: 32),

            // Buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  DateTime? nextEligibleTime = await scheduler.markAsTaken(dose.id);
                  if (context.mounted) {
                    Navigator.pop(context); // Close the reminder dialog

                    if (nextEligibleTime != null) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text(
                            'Medication Logged',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          content: Text(
                            'Your next eligible time to take ${dose.name} is ${TimeOfDay.fromDateTime(nextEligibleTime).format(ctx)}.\n\nAny scheduled doses before this time have been skipped for your safety.',
                            style: const TextStyle(fontSize: 16),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text(
                                'OK',
                                style: TextStyle(
                                  color: Color(0xFF51A77B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF51A77B),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Taken',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  scheduler.snoozeDose(dose.id);
                  Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Remind Me Later',
                  style: TextStyle(color: Colors.black87, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  scheduler.skipDose(dose.id);
                  Navigator.pop(context);
                },
                child: const Text(
                  'Skip',
                  style: TextStyle(color: Colors.red, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
