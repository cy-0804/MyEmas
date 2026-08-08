import 'dart:async';
import 'package:flutter/material.dart';
import '../models/medication_dose.dart';
import '../models/dose_status.dart';
import '../repositories/medication_repository.dart';
import 'notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
// Note: In real production code, we'd inject dependencies via Riverpod/GetIt.

class ReminderScheduler {
  static final ReminderScheduler _instance = ReminderScheduler._internal();
  static ReminderScheduler get instance => _instance;

  MedicationDoseRepository? _repository;
  ReminderNotificationService? _notificationService;

  // Stream to notify UI of active reminders
  final _activeReminderController = StreamController<MedicationDose>.broadcast();
  Stream<MedicationDose> get activeReminders => _activeReminderController.stream;

  // Background FSM check timer
  Timer? _fsmTimer;

  ReminderScheduler._internal();

  void init(MedicationDoseRepository repo, ReminderNotificationService notifService) {
    _repository = repo;
    _notificationService = notifService;
    _startFsmLoop();
  }

  void _startFsmLoop() {
    // Run FSM checks every minute to transition states
    _fsmTimer?.cancel();
    _evaluateFsm();
    _fsmTimer = Timer.periodic(const Duration(minutes: 1), (_) => _evaluateFsm());
  }

  void evaluateFsmNow() {
    _evaluateFsm();
  }

  /// Initial entry point to schedule a new dose
  Future<void> scheduleDose(MedicationDose dose) async {
    final allDoses = await _repository!.getAllDoses();
    
    // Do not reschedule if this exact dose already exists
    final existing = allDoses.where((d) => d.id == dose.id).toList();
    if (existing.isNotEmpty) {
      return;
    }

    // Prevent overlapping logically by checking previous doses
    final conflictingDoses = allDoses.where((d) => 
      d.status == DoseStatus.scheduled && 
      d.id != dose.id &&
      d.scheduledTime.difference(dose.scheduledTime).inMinutes.abs() < 30
    ).toList();

    if (conflictingDoses.isNotEmpty) {
      // Delay this dose by 30 mins to prevent overlap
      final delayedTime = dose.scheduledTime.add(const Duration(minutes: 30));
      dose = MedicationDose(
        id: dose.id,
        medicationId: dose.medicationId,
        name: dose.name,
        dosage: dose.dosage,
        instruction: dose.instruction,
        photo: dose.photo,
        scheduledTime: delayedTime,
        windowEnd: dose.windowEnd.add(const Duration(minutes: 30)),
      );
    }

    dose.status = DoseStatus.scheduled;
    await _repository!.saveDose(dose);
    await _notificationService!.scheduleDoseReminders(dose);
  }

  /// Core FSM logic evaluated periodically
  Future<void> _evaluateFsm() async {
    final now = DateTime.now();
    final doses = await _repository!.getAllDoses();

    for (var dose in doses) {
      bool updated = false;

      switch (dose.status) {
        case DoseStatus.scheduled:
          if (now.isAfter(dose.scheduledTime) || now.isAtSameMomentAs(dose.scheduledTime)) {
            // Transition: Scheduled -> Reminder Active
            dose.status = DoseStatus.reminderActive;
            _activeReminderController.add(dose); // Notify UI to show dialog
            
            // Show system-level overlay if app is in background
            try {
               final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
               if (hasPermission) {
                  await FlutterOverlayWindow.showOverlay(
                    enableDrag: false,
                    overlayTitle: "Medication Reminder",
                    overlayContent: dose.name,
                    flag: OverlayFlag.defaultFlag,
                    alignment: OverlayAlignment.center,
                    visibility: NotificationVisibility.visibilityPublic,
                    positionGravity: PositionGravity.auto,
                  );
               }
            } catch (e) {
               debugPrint("Overlay error: $e");
            }

            updated = true;
          }
          break;
          
        case DoseStatus.reminderActive:
          if (now.isAfter(dose.windowEnd)) {
            // Transition: Reminder Active -> Missed
            dose.status = DoseStatus.missed;
            await _notificationService!.cancelDoseReminders(dose.id);
            await _notifyCaregiverMissed(dose);
            updated = true;
          } else {
            // Still active. The pre-scheduled notifications will handle background pings.
            // If the app is open, we can periodically trigger the UI dialog stream
            _activeReminderController.add(dose);
          }
          break;
          
        case DoseStatus.taken:
        case DoseStatus.lateTaken:
        case DoseStatus.missed:
        case DoseStatus.skipped:
          // Terminal states, no action needed in FSM loop
          break;
      }

      if (updated) {
        await _repository!.saveDose(dose);
      }
    }
  }

  /// Fired when user clicks "Taken"
  Future<DateTime?> markAsTaken(String doseId) async {
    final dose = await _repository!.getDose(doseId);
    if (dose == null) return null;

    final now = DateTime.now();
    dose.actualTakenTime = now;

    // Check if within window
    if (now.isBefore(dose.windowEnd) || now.isAtSameMomentAs(dose.windowEnd)) {
      dose.status = DoseStatus.taken;
    } else {
      dose.status = DoseStatus.lateTaken;
    }

    await _notificationService!.cancelDoseReminders(doseId);
    await _repository!.saveDose(dose);

    DateTime? nextEligibleTime;
    
    // Interval Protection Logic
    if (dose.minIntervalHours > 0) {
      nextEligibleTime = now.add(Duration(hours: dose.minIntervalHours));
      final allDoses = await _repository!.getAllDoses();
      
      for (var futureDose in allDoses) {
        // Find other scheduled doses for the EXACT SAME medication for today
        if (futureDose.medicationId == dose.medicationId && 
            futureDose.id != dose.id && 
            (futureDose.status == DoseStatus.scheduled || futureDose.status == DoseStatus.reminderActive)) {
          
          if (futureDose.scheduledTime.isBefore(nextEligibleTime)) {
            // Cancel this unsafe dose
            futureDose.status = DoseStatus.skipped; // Marking as skipped for safety
            await _notificationService!.cancelDoseReminders(futureDose.id);
            await _repository!.saveDose(futureDose);
            _syncToCloud(futureDose, reason: 'skipped_safety');
            debugPrint('Interval Protection: Cancelled dose ${futureDose.id} scheduled at ${futureDose.scheduledTime}');
          }
        }
      }
    }
    // Reset consecutive_missed_count on success
    try {
      await Supabase.instance.client
          .from('medications')
          .update({'consecutive_missed_count': 0})
          .eq('medication_id', dose.medicationId);
    } catch (e) {
      debugPrint('Error resetting missed count: $e');
    }

    // Sync to backend/Supabase
    _syncToCloud(dose);
    return nextEligibleTime;
  }

  /// Fired when user clicks "Remind Me Later"
  Future<void> snoozeDose(String doseId) async {
    final dose = await _repository!.getDose(doseId);
    if (dose == null) return;

    dose.snoozeCount++;
    await _repository!.saveDose(dose);

    // Cancel current notifications
    await _notificationService!.cancelDoseReminders(doseId);

    // Temporarily adjust scheduled time to 10 mins from now to regenerate FSM timeline
    final snoozedDose = MedicationDose(
      id: dose.id,
      medicationId: dose.medicationId,
      name: dose.name,
      dosage: dose.dosage,
      instruction: dose.instruction,
      photo: dose.photo,
      scheduledTime: DateTime.now().add(const Duration(minutes: 10)),
      windowEnd: dose.windowEnd,
      status: DoseStatus.scheduled, // Send back to scheduled FSM
      snoozeCount: dose.snoozeCount,
    );

    await _repository!.saveDose(snoozedDose);
    await _notificationService!.scheduleDoseReminders(snoozedDose);
  }

  /// Fired when user clicks "Skip"
  Future<void> skipDose(String doseId) async {
    final dose = await _repository!.getDose(doseId);
    if (dose == null) return;

    dose.status = DoseStatus.skipped;
    await _notificationService!.cancelDoseReminders(doseId);
    await _repository!.saveDose(dose);

    // Notify Caregiver
    _notifyCaregiverMissed(dose, skipped: true);
    _syncToCloud(dose);
  }

  Future<void> _notifyCaregiverMissed(MedicationDose dose, {bool skipped = false}) async {
    debugPrint('Caregiver Escalation: ${dose.name} was ${skipped ? 'skipped' : 'missed'}.');
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser?.id;
      if (uid == null) return;

      // Find caregiver id
      final careLink = await db.from('care_link').select('caregiver_id').eq('elderly_id', uid).maybeSingle();
      if (careLink == null) return;
      final caregiverId = careLink['caregiver_id'];

      // Get current missed count
      final medRes = await db.from('medications').select('consecutive_missed_count').eq('medication_id', dose.medicationId).maybeSingle();
      int missedCount = 0;
      if (medRes != null && medRes['consecutive_missed_count'] != null) {
        missedCount = medRes['consecutive_missed_count'] as int;
      }
      missedCount++;

      // Update count
      await db.from('medications').update({'consecutive_missed_count': missedCount}).eq('medication_id', dose.medicationId);

      // Create Alert
      await db.from('medication_alerts').insert({
        'elderly_id': uid,
        'caregiver_id': caregiverId,
        'medication_id': dose.medicationId,
        'medication_name': dose.name,
        'scheduled_time': dose.scheduledTime.toUtc().toIso8601String(),
        'missed_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'Pending',
        'consecutive_missed_count': missedCount,
      });
      
      // Also write to emergency_logs to reuse existing notification dispatch mechanism for caregiver
      final msg = 'Medication Missed: ${dose.name}';
      await db.from('emergency_logs').insert({
        'link_id': careLink['link_id'] ?? '',
        'status': msg,
        'location': 'Medication Non-Adherence',
        'caregiver_id': caregiverId,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

    } catch (e) {
      debugPrint('Error in _notifyCaregiverMissed: $e');
    }
  }

  void _syncToCloud(MedicationDose dose, {String? reason}) async {
    // Synchronize the status to medication_logs in Supabase
    debugPrint('Cloud Sync: ${dose.name} -> ${dose.status.name}');
    
    try {
      final targetDate = dose.actualTakenTime ?? DateTime.now();
      
      // We map our DoseStatus to the DB enum if possible, or string.
      // E.g., 'taken', 'missed', 'skipped', 'late_taken'.
      String statusStr = 'missed';
      if (dose.status == DoseStatus.taken) {
        statusStr = 'taken';
      } else if (dose.status == DoseStatus.lateTaken) statusStr = 'late_taken';
      else if (dose.status == DoseStatus.skipped) statusStr = reason ?? 'skipped';
      
      // Fetch current missed count to log it
      int missedCount = 0;
      final medRes = await Supabase.instance.client.from('medications').select('consecutive_missed_count').eq('medication_id', dose.medicationId).maybeSingle();
      if (medRes != null && medRes['consecutive_missed_count'] != null) {
        missedCount = medRes['consecutive_missed_count'] as int;
      }

      await Supabase.instance.client.from('medication_logs').insert({
        'medication_id': dose.medicationId,
        'logged_at': targetDate.toUtc().toIso8601String(),
        'status': statusStr,
        'scheduled_time': dose.scheduledTime.toUtc().toIso8601String(),
        'consecutive_missed_count': missedCount,
      });
    } catch (e) {
      debugPrint('Error syncing dose to cloud: $e');
    }
  }

  void dispose() {
    _fsmTimer?.cancel();
    _activeReminderController.close();
  }
}
