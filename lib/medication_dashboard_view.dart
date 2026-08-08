import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'session_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'main.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'schedule_dashboard_view.dart';
import 'notification_dialogs.dart';
import 'medication_reminder/models/medication_dose.dart';
import 'medication_reminder/services/reminder_scheduler.dart';

// ─── colour tokens (matching app design system) ───────────────────────────────
const _kPrimary = Color(0xFF51A77B);
const _kBlue = Color(0xFF00539E);
const _kBg = Color(0xFFF6F8FA);
const _kCard = Colors.white;
const _kTextDark = Color(0xFF27252E);
const _kTextGrey = Color(0xFF6C7278);

// ─── notification helper ──────────────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _notifPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initMedicationNotifications() async {
  try {
    tz.initializeTimeZones();
    final location = tz.getLocation('Asia/Kuala_Lumpur');
    tz.setLocalLocation(location);
    const android = AndroidInitializationSettings('ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _notifPlugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          final parts = payload.split('|');
          if (parts.length >= 4) {
            final medId = parts[0];
            final name = parts[1];
            final dosage = parts[2];
            final instruction = parts[3];

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showDialogWhenReady(medId, name, dosage, instruction);
            });
          }
        }
      },
    );

    // Request notification permission if not already allowed
    final status = await Permission.notification.status;
    if (status.isDenied) {
      final res = await Permission.notification.request();
      if (res.isPermanentlyDenied) {
        openAppSettings();
      }
    }

    // Request exact alarm permission if not already granted on Android 12+
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }

    final launchDetails = await _notifPlugin.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      final payload = launchDetails.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        final parts = payload.split('|');
        if (parts.length >= 4) {
          final medId = parts[0];
          final name = parts[1];
          final dosage = parts[2];
          final instruction = parts[3];

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showDialogWhenReady(medId, name, dosage, instruction);
          });
        }
      }
    }
  } catch (e) {
    debugPrint('Failed to initialize local notifications: $e');
  }
}

Future<void> _triggerNotificationAndOverlay(
  int id,
  String title,
  String body,
  String payload,
) async {
  // Show standard notification
  await _notifPlugin.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'medication_channel',
        'Medication Reminders',
        channelDescription: 'Reminds you to take your medication',
        importance: Importance.max,
        priority: Priority.max,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    payload: payload,
  );

  // Overlay window code removed due to crashes
}

Widget _buildMedPhoto(
  String url, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  if (url.startsWith('data:image')) {
    final base64Str = url.split(',').last;
    return Image.memory(
      base64Decode(base64Str),
      width: width,
      height: height,
      fit: fit,
    );
  }
  return Image.network(url, width: width, height: height, fit: fit);
}

void _showDialogWhenReady(
  String medId,
  String name,
  String dosage,
  String instruction,
) {
  Future.doWhile(() async {
    final context = navigatorKey.currentContext;
    if (context != null) {
      showMedicationReminderDialog(context, medId, name, dosage, instruction);
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 200));
    return true;
  }).timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      debugPrint(
        'Timeout waiting for navigator context to show reminder dialog.',
      );
    },
  );
}

String _formatWhenToTake(String? val, [BuildContext? context]) {
  if (val == null) return 'Not specified';
  if (val.contains(':')) {
    try {
      final parts = val.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final timeOfDay = TimeOfDay(hour: hour, minute: minute);
      if (context != null) {
        return timeOfDay.format(context);
      }
      final amPm = hour >= 12 ? 'PM' : 'AM';
      final formattedHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      final formattedMinute = minute.toString().padLeft(2, '0');
      return '$formattedHour:$formattedMinute $amPm';
    } catch (_) {}
  }
  return val;
}

// ─── Pure-Dart reminder engine (no AlarmManager permissions needed) ──────────
//
// Strategy:
//   1. For each medication, compute seconds until today's reminder time.
//   2. Use Future.delayed(duration, () => show()) for the first alert.
//   3. After that, use Timer.periodic every 60 s to fire follow-ups until
//      the user logs "taken" or midnight resets.
//
// This is identical in mechanism to the test notification that already works.

// Track active follow-up timers keyed by medication id
final Map<String, Timer> _followUpTimers = {};
// Track pending first-alert futures keyed by medication id (cancel via flag)
final Map<String, bool> _cancelledAlerts = {};
// Track initial and snooze timers
final Map<String, Timer> _initialTimers = {};

/// Cancel all scheduled reminders for one medication (call on delete or mark-taken).
void cancelMedicationReminder(String medId) {
  _cancelledAlerts[medId] = true;
  _initialTimers[medId]?.cancel();
  _initialTimers.remove(medId);
  _followUpTimers[medId]?.cancel();
  _followUpTimers.remove(medId);
  debugPrint('cancelMedicationReminder: cancelled reminders for $medId');
}

/// Cancel ALL medication reminders (call before re-scheduling).
void cancelAllMedicationReminders() {
  for (final id in _cancelledAlerts.keys) {
    _cancelledAlerts[id] = true;
  }
  for (final t in _initialTimers.values) {
    t.cancel();
  }
  _initialTimers.clear();
  for (final t in _followUpTimers.values) {
    t.cancel();
  }
  _followUpTimers.clear();
  _notifPlugin.cancelAll();
  debugPrint('cancelAllMedicationReminders: cleared everything');
}

/// Returns the hour and minute for a medication's whenToTake field.
/// Returns null if the medication should not have a scheduled reminder.
(int hour, int minute)? _parseReminderTime(String? whenToTake) {
  if (whenToTake == null || whenToTake.isEmpty || whenToTake == 'As needed') {
    return null;
  }

  // 1. Try to find custom session time from SessionManager
  try {
    final session = SessionManager().sessions.firstWhere(
      (s) => s.name.toLowerCase() == whenToTake.toLowerCase() || s.id.toLowerCase() == whenToTake.toLowerCase(),
    );
    return (session.time.hour, session.time.minute);
  } catch (_) {
    // Not found in custom sessions, fall back to defaults
  }

  if (whenToTake == 'Morning') return (8, 0);
  if (whenToTake == 'Afternoon') return (12, 0);
  if (whenToTake == 'Evening') return (18, 0);
  if (whenToTake == 'Night') return (23, 49);
  if (whenToTake.contains(':')) {
    try {
      final p = whenToTake.split(':');
      return (int.parse(p[0]), int.parse(p[1]));
    } catch (_) {}
  }
  return null;
}

/// Schedules a reminder for one medication using the FSM engine.
void scheduleMedicationReminder(Medication med) {
  final parsed = _parseReminderTime(med.whenToTake);
  if (parsed == null) return;

  final (hour, minute) = parsed;
  final now = DateTime.now();
  final reminderToday = DateTime(now.year, now.month, now.day, hour, minute);

  if (now.isAfter(reminderToday.add(const Duration(hours: 4)))) {
    // Already completely missed the window for today.
    return;
  }

  final dose = MedicationDose(
    id: '${med.id}_${reminderToday.millisecondsSinceEpoch}',
    medicationId: med.id,
    name: med.name,
    dosage: med.dosage,
    instruction: med.instruction,
    photo: med.photo,
    scheduledTime: reminderToday,
    windowEnd: reminderToday.add(const Duration(hours: 4)), // default 4-hour window
  );

  // Mark in local maps so syncAll doesn't try to constantly restart
  _initialTimers[med.id]?.cancel();
  _cancelledAlerts[med.id] = false;

  ReminderScheduler.instance.scheduleDose(dose);
  debugPrint('FSM: Scheduled real dose for ${med.name} at $reminderToday');
}

/// Starts a recursive chain of one-shot follow-up timers.
/// Uses the same mechanism as Future.delayed (proven to work).
void _startFollowUpTimer(
  String medId,
  String name,
  String? dosage,
  String? instruction,
  String payload,
) {
  _scheduleNextFollowUp(medId, name, dosage, instruction, payload, 0);
}

void _scheduleNextFollowUp(
  String medId,
  String name,
  String? dosage,
  String? instruction,
  String payload,
  int count,
) {
  int intervalMins = 5; // Default High

  // Store the timer so cancelMedicationReminder can cancel it
  _followUpTimers[medId] = Timer(Duration(minutes: intervalMins), () async {
    // Check if cancelled locally (deleted via app or marked taken)
    if (_cancelledAlerts[medId] == true) {
      _followUpTimers.remove(medId);
      debugPrint(
        '_scheduleNextFollowUp: cancelled locally for $name (#$count)',
      );
      return;
    }

    // Stop at midnight — new day resets reminders
    final now = DateTime.now();
    if (now.hour == 0 && now.minute < 2) {
      _followUpTimers.remove(medId);
      debugPrint('_scheduleNextFollowUp: midnight reset for $name');
      return;
    }

    // ── Supabase existence check ──────────────────────────────────────────────
    // Verify medication still exists in DB (catches direct Supabase deletions)
    try {
      final existRes = await Supabase.instance.client
          .from('medications')
          .select('medication_id')
          .eq('medication_id', medId)
          .maybeSingle();
      if (existRes == null) {
        // Medication was deleted directly from Supabase
        _cancelledAlerts[medId] = true;
        _followUpTimers.remove(medId);
        debugPrint(
          '_scheduleNextFollowUp: $name no longer in DB — stopping reminders',
        );
        return;
      }
    } catch (e) {
      debugPrint('_scheduleNextFollowUp: DB check error for $name: $e');
      // On error, continue — don't stop reminders due to a network hiccup
    }

    // ── Already taken today check ─────────────────────────────────────────────
    try {
      final todayStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).toUtc().toIso8601String();
      final takenRes = await Supabase.instance.client
          .from('medication_logs')
          .select('medication_id')
          .eq('medication_id', medId)
          .eq('status', 'taken')
          .gte('logged_at', todayStart)
          .maybeSingle();
      if (takenRes != null) {
        // Already logged as taken today — stop reminders
        _cancelledAlerts[medId] = true;
        _followUpTimers.remove(medId);
        debugPrint(
          '_scheduleNextFollowUp: $name already taken today — stopping reminders',
        );
        return;
      }
    } catch (e) {
      debugPrint('_scheduleNextFollowUp: taken check error for $name: $e');
    }
    // ─────────────────────────────────────────────────────────────────────────

    final nextCount = count + 1;
    debugPrint('_scheduleNextFollowUp: firing follow-up #$nextCount for $name');

    try {
      await _triggerNotificationAndOverlay(
        medId.hashCode,
        '⚠️ Reminder: Take $name! (#$nextCount)',
        'You haven\'t logged it yet. Please take ${dosage ?? ""} ${instruction ?? "as directed"}.',
        payload,
      );
      debugPrint('_scheduleNextFollowUp: showed follow-up #$nextCount');
    } catch (e) {
      debugPrint(
        '_scheduleNextFollowUp: ERROR showing follow-up #$nextCount: $e',
      );
    }

    // Schedule the next follow-up in the chain
    _scheduleNextFollowUp(medId, name, dosage, instruction, payload, nextCount);
  });
}

/// Sync all medication reminders.
/// Preserves active follow-up timers for medications still in the list.
/// Only cancels timers for medications that have been removed.
Future<void> syncAllMedicationReminders([List<Medication>? medications]) async {
  try {
    List<Medication> meds = medications ?? [];
    if (medications == null) {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      // Do not schedule elderly-side medication alarms for caregivers.
      // Caregivers get their own separate missed/low-stock alerts via SosNotificationService.
      final userRes = await Supabase.instance.client
          .from('users')
          .select('role_id')
          .eq('user_id', uid)
          .maybeSingle();
      if (userRes != null && userRes['role_id'] == 'caregiver') {
        cancelAllMedicationReminders();
        return;
      }

      final schedRes = await Supabase.instance.client
          .from('schedule')
          .select('schedule_id')
          .eq('elderly_id', uid);

      final scheduleIds = (schedRes as List)
          .map((s) => s['schedule_id'] as String)
          .toList();

      if (scheduleIds.isNotEmpty) {
        final medRes = await Supabase.instance.client
            .from('medications')
            .select()
            .inFilter('schedule_id', scheduleIds);
        meds = (medRes as List)
            .map((m) => Medication.fromMap(m as Map<String, dynamic>))
            .toList();
      }
    }

    // Cancel timers ONLY for medications no longer in the list
    final newMedIds = meds.map((m) => m.id).toSet();
    final staleIds = _cancelledAlerts.keys.toSet().difference(newMedIds);
    for (final id in staleIds) {
      cancelMedicationReminder(id);
    }

    debugPrint(
      'syncAllMedicationReminders: syncing ${meds.length} medications (${staleIds.length} stale removed)...',
    );

    final uid = Supabase.instance.client.auth.currentUser?.id;
    final todayStr = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    for (final med in meds) {
      final isExpired = med.expirationDate != null && med.expirationDate!.isBefore(todayStr);

      if (isExpired) {
        debugPrint('  → ${med.name}: expired, skipping reminder');
        cancelMedicationReminder(med.id);
      } else {
        // Skip if already actively following up — don't restart the timer
        if (_followUpTimers.containsKey(med.id)) {
          debugPrint('  → ${med.name}: follow-up already active, skipping');
        } else {
          scheduleMedicationReminder(med);
        }
      }

      // Check Expiration / Low Stock
      if (uid != null) {
        bool shouldAlert = false;
        String msg = '';
        if (med.stock != null && med.stock! < 5) {
          shouldAlert = true;
          msg =
              'Low Stock: ${med.name} (${med.stock} ${med.stockUnit ?? "left"})';
        } else if (med.expirationDate != null) {
          final diff = med.expirationDate!.difference(DateTime.now()).inDays;
          if (diff < 0) {
            shouldAlert = true;
            msg = 'Expired Medicine: ${med.name}';
          } else if (diff <= 7) {
            shouldAlert = true;
            msg = 'Expiring Soon: ${med.name}';
          }
        }

        if (shouldAlert) {
          try {
            final nowStr = DateTime.now().toUtc().toIso8601String().substring(
              0,
              10,
            );

            // Check if caregiver alert already sent today
            final caregiverRes = await Supabase.instance.client
                .from('care_link')
                .select('link_id, caregiver_id')
                .eq('elderly_id', uid)
                .maybeSingle();

            if (caregiverRes != null) {
              final alertExists = await Supabase.instance.client
                  .from('emergency_logs')
                  .select('alert_id')
                  .eq('link_id', caregiverRes['link_id'])
                  .eq('status', msg)
                  .gte('timestamp', nowStr)
                  .maybeSingle();

              if (alertExists == null) {
                // Notify Caregiver
                await Supabase.instance.client.from('emergency_logs').insert({
                  'link_id': caregiverRes['link_id'],
                  'status': msg,
                  'location': 'Medicine Expiration/Stock',
                  'caregiver_id': caregiverRes['caregiver_id'],
                  'timestamp': DateTime.now().toUtc().toIso8601String(),
                });

                // Notify Elderly (only once a day, aligned with caregiver insert)
                await _triggerNotificationAndOverlay(
                  msg.hashCode,
                  '⚠️ Medicine Alert',
                  msg,
                  'alert|$msg',
                );
              }
            }
          } catch (e) {
            debugPrint('Error pushing alert for ${med.name}: $e');
          }
        }
      }
    }

    debugPrint('syncAllMedicationReminders: done.');
  } catch (e) {
    debugPrint('syncAllMedicationReminders error: $e');
  }
}

void showMedicationReminderDialog(
  BuildContext context,
  String medId,
  String name,
  String dosage,
  String instruction,
) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Stack(
        children: [
          Positioned(
            right: 12,
            top: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 18, color: Colors.black54),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Time To Take Medicine !'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'League Spartan',
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF27252E),
                  ),
                ),
                SizedBox(height: 24),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00539E),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00539E).withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.medication_rounded,
                    size: 68,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF27252E),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  dosage,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                SizedBox(height: 6),
                Text(
                  instruction,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          try {
                            // Cancel all pending follow-up reminders for this medication
                            cancelMedicationReminder(medId);
                            await _notifPlugin.cancel(medId.hashCode);

                            await Supabase.instance.client
                                .from('medication_logs')
                                .insert({
                                  'medication_id': medId,
                                  'status': 'taken',
                                });
                          } catch (e) {
                            debugPrint('Error saving taken log: $e');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF51A77B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: Text(
                          'I have taken'.tr(),
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          // Pause follow-up loop, then snooze 5 min via Timer
                          cancelMedicationReminder(medId);
                          _cancelledAlerts[medId] = false;
                          debugPrint(
                            'Remind Later: snoozed $name for 5 minutes',
                          );
                          _initialTimers[medId] = Timer(const Duration(minutes: 5), () async {
                            _initialTimers.remove(medId);
                            if (_cancelledAlerts[medId] == true) return;
                            // Show the snooze notification
                            await _triggerNotificationAndOverlay(
                              medId.hashCode,
                              '💊 Reminder: Time to take $name!',
                              '${dosage.isNotEmpty ? dosage : "Take"} — $instruction',
                              '$medId|$name|$dosage|$instruction',
                            );
                            debugPrint(
                              'Remind Later: snooze fired for $name, restarting follow-ups',
                            );
                            _startFollowUpTimer(
                              medId,
                              name,
                              dosage.isNotEmpty ? dosage : null,
                              instruction.isNotEmpty ? instruction : null,
                              '$medId|$name|$dosage|$instruction',
                            );
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF27252E)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Remind Later'.tr(),
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF27252E),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> showMedicationReminder({
  required String name,
  required String dosage,
  required String instruction,
}) async {
  await _triggerNotificationAndOverlay(
    name.hashCode,
    '💊 Time To Take Medicine!',
    '$name — $dosage. $instruction',
    '',
  );
}

// ─── Medication model ─────────────────────────────────────────────────────────
class Medication {
  final String id;
  final String name;
  final String? dosage;
  final String? whenToTake;
  final String? instruction;
  final int? stock;
  final String? notes;
  final String? scheduleId;
  final DateTime? expirationDate;
  final String? photo;
  final String? stockUnit;
  final int minIntervalHours;

  Medication({
    required this.id,
    required this.name,
    this.dosage,
    this.whenToTake,
    this.instruction,
    this.stock,
    this.notes,
    this.scheduleId,
    this.expirationDate,
    this.photo,
    this.stockUnit,
    this.minIntervalHours = 4,
  });

  factory Medication.fromMap(Map<String, dynamic> m) {
    String? rawNotes = m['medical_notes']?.toString();
    String? sUnit;
    if (rawNotes != null && rawNotes.contains('|stock_unit:')) {
      final parts = rawNotes.split('|stock_unit:');
      rawNotes = parts[0];
      sUnit = parts[1];
    }

    return Medication(
      id: m['medication_id']?.toString() ?? '',
      name: m['medication_name']?.toString() ?? '',
      dosage: m['dosage']?.toString(),
      whenToTake: m['when_to_take']?.toString(),
      instruction: m['instruction']?.toString(),
      stock: m['medication_stock'] != null
          ? int.tryParse(m['medication_stock'].toString())
          : null,
      notes: rawNotes,
      scheduleId: m['schedule_id']?.toString(),
      expirationDate: m['expiration_date'] != null
          ? DateTime.tryParse(m['expiration_date'].toString())
          : null,
      photo: m['photo']?.toString(),
      stockUnit: sUnit,
      minIntervalHours: m['min_interval_hours'] != null
          ? int.tryParse(m['min_interval_hours'].toString()) ?? 4
          : 4,
    );
  }
}

// ─── Medication Log model ─────────────────────────────────────────────────────
class MedicationLog {
  final String id;
  final String medicationId;
  final String status; // 'taken' | 'missed'
  final DateTime loggedAt;
  String? medicationName;

  MedicationLog({
    required this.id,
    required this.medicationId,
    required this.status,
    required this.loggedAt,
    this.medicationName,
  });

  factory MedicationLog.fromMap(Map<String, dynamic> m) => MedicationLog(
    id: m['log_id']?.toString() ?? '',
    medicationId: m['medication_id']?.toString() ?? '',
    status: m['status']?.toString() ?? '',
    loggedAt: () {
      if (m['logged_at'] != null) {
        String s = m['logged_at'].toString();
        if (!s.endsWith('Z')) s += 'Z';
        return DateTime.tryParse(s)?.toLocal() ?? DateTime.now();
      }
      return DateTime.now();
    }(),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// MEDICATION DASHBOARD VIEW  (Tab inside ElderlyDashboard)
// ═════════════════════════════════════════════════════════════════════════════
class MedicationDashboardView extends StatefulWidget {
  final String? elderlyId;
  final bool isStandalone;
  const MedicationDashboardView({
    super.key,
    this.elderlyId,
    this.isStandalone = false,
  });
  @override
  State<MedicationDashboardView> createState() =>
      _MedicationDashboardViewState();
}

class _MedicationDashboardViewState extends State<MedicationDashboardView> {
  List<Medication> _medications = [];
  List<MedicationLog> _selectedDateLogs = [];
  List<MedicationLog> _actualTodayLogs = [];
  bool _loading = true;
  DateTime _selectedLogDate = DateTime.now();
  bool _expiredPromptShown = false;

  Map<String, List<Medication>> get _groupedMeds {
    final map = <String, List<Medication>>{};
    for (final med in _medications) {
      final session = med.whenToTake ?? 'Other';
      if (map[session] != null) {
        bool exists = map[session]!.any((m) => m.name == med.name);
        if (exists) continue;
      }
      map.putIfAbsent(session, () => []).add(med);
    }
    return map;
  }

  List<Medication> get _expiredMeds {
    final today = DateTime.now();
    final todayStr = DateTime(today.year, today.month, today.day);
    final expired = <Medication>[];
    final seen = <String>{};
    for (final m in _medications) {
      if (m.expirationDate == null) continue;
      if (m.expirationDate!.isBefore(todayStr)) {
        final key = m.name.trim().toLowerCase();
        if (!seen.contains(key)) {
          seen.add(key);
          expired.add(m);
        }
      }
    }
    return expired;
  }

  void _showExpiredMedsDialog(List<String> meds) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                'Expired Medication!'.tr(),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Text(
            '${'Please stop taking the following expired medications immediately:'.tr()}\n\n• ${meds.join('\n• ')}',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: Text('I Understand'.tr()),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    initMedicationNotifications();
    _load();
  }

  Future<void> _load() async {
    if (_medications.isEmpty) setState(() => _loading = true);
    try {
      final uid =
          widget.elderlyId ?? Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      // Load medications via schedule (elderly's schedules → medications)
      final schedRes = await Supabase.instance.client
          .from('schedule')
          .select()
          .eq('elderly_id', uid);

      final now = DateTime.now();
      final List<String> scheduleIds = [];

      for (var s in schedRes as List) {
        try {
          final record = ScheduleRecord.fromMap(s as Map<String, dynamic>);
          bool isToday = false;
          // Medication schedules (title starts with 'Take') always show daily
          if (record.title.trim().toLowerCase().startsWith('take ')) {
            isToday = true;
          } else if (record.scheduleDateTime.year == now.year &&
              record.scheduleDateTime.month == now.month &&
              record.scheduleDateTime.day == now.day) {
            isToday = true;
          } else if (record.repeatFrequency == 'Daily') {
            isToday = true;
          } else if (record.repeatFrequency == 'Weekly' &&
              record.scheduleDateTime.weekday == now.weekday) {
            isToday = true;
          } else if (record.repeatFrequency == 'Monthly' &&
              record.scheduleDateTime.day == now.day) {
            isToday = true;
          }

          if (isToday) {
            scheduleIds.add(record.id);
          }
        } catch (e) {
          // ignore parsing errors
        }
      }

      List<Medication> meds = [];
      if (scheduleIds.isNotEmpty) {
        final medRes = await Supabase.instance.client
            .from('medications')
            .select()
            .inFilter('schedule_id', scheduleIds);
        meds = (medRes as List)
            .map((m) => Medication.fromMap(m as Map<String, dynamic>))
            .toList();
      }

      // Load selected date's logs
      final start = DateTime(
        _selectedLogDate.year,
        _selectedLogDate.month,
        _selectedLogDate.day,
      );
      final end = start.add(const Duration(days: 1));

      List<MedicationLog> logs = [];
      List<MedicationLog> actualTodayLogsList = [];
      if (meds.isNotEmpty) {
        final medIds = meds.map((m) => m.id).toList();

        // Fetch logs for the selected date
        final logRes = await Supabase.instance.client
            .from('medication_logs')
            .select()
            .inFilter('medication_id', medIds)
            .gte('logged_at', start.toUtc().toIso8601String())
            .lt('logged_at', end.toUtc().toIso8601String())
            .order('logged_at', ascending: false);
        logs = (logRes as List)
            .map((l) => MedicationLog.fromMap(l as Map<String, dynamic>))
            .toList();

        // Fetch logs for ACTUAL today (for the checkboxes in "Today's Medicine")
        final actualStart = DateTime(now.year, now.month, now.day);
        final actualEnd = actualStart.add(const Duration(days: 1));
        final actualLogRes = await Supabase.instance.client
            .from('medication_logs')
            .select()
            .inFilter('medication_id', medIds)
            .gte('logged_at', actualStart.toUtc().toIso8601String())
            .lt('logged_at', actualEnd.toUtc().toIso8601String());
        actualTodayLogsList = (actualLogRes as List)
            .map((l) => MedicationLog.fromMap(l as Map<String, dynamic>))
            .toList();

        // Attach names
        final medMap = {for (var m in meds) m.id: m.name};
        for (final log in logs) {
          log.medicationName = medMap[log.medicationId];
        }
      }

      if (mounted) {
        setState(() {
          _medications = meds;
          _selectedDateLogs = logs;
          _actualTodayLogs = actualTodayLogsList;
          _loading = false;
        });
        syncAllMedicationReminders(meds);

        final expired = _expiredMeds;
        if (expired.isNotEmpty && !_expiredPromptShown) {
          _expiredPromptShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showExpiredMedsDialog(expired.map((e) => e.name).toList());
          });
        }
      }
    } catch (e) {
      debugPrint('Medication load error: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load Meds Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markTaken(Medication med) async {
    try {
      await Supabase.instance.client.from('medication_logs').insert({
        'medication_id': med.id,
        'status': 'taken',
        'logged_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 1. Auto recount stock
      if (med.stock != null && med.stock! > 0) {
        int takenAmount = 1;
        if (med.dosage != null) {
          final amt = int.tryParse(med.dosage!.split(' ').first);
          if (amt != null && amt > 0) takenAmount = amt;
        }
        int newStock = med.stock! - takenAmount;
        if (newStock < 0) newStock = 0;

        final uid =
            widget.elderlyId ?? Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) {
          final checkSchedRes = await Supabase.instance.client
              .from('schedule')
              .select('schedule_id')
              .eq('elderly_id', uid);
          final elderlySchedIds = (checkSchedRes as List)
              .map((s) => s['schedule_id'])
              .toList();

          if (elderlySchedIds.isNotEmpty) {
            await Supabase.instance.client
                .from('medications')
                .update({'medication_stock': newStock})
                .eq('medication_name', med.name)
                .inFilter('schedule_id', elderlySchedIds);
          }
        } else {
          await Supabase.instance.client
              .from('medications')
              .update({'medication_stock': newStock})
              .eq('medication_id', med.id);
        }
      }

      // 2. Mark schedule as done or advance for recurring
      if (med.scheduleId != null) {
        final schedRes = await Supabase.instance.client
            .from('schedule')
            .select()
            .eq('schedule_id', med.scheduleId!)
            .maybeSingle();

        if (schedRes != null) {
          final oldNotes = schedRes['notes'] as String? ?? '';
          final meta = ScheduleMetadata.fromNotes(oldNotes);

          final newNotes = ScheduleMetadata.toNotesString(
            notesText: meta.notesText,
            type: meta.scheduleType,
            priority: meta.priority,
            status: 'done', // Marked done
            allDay: meta.allDay,
            endDateTime: meta.endDateTime,
            reminderTime: meta.reminderTime,
            repeat: meta.repeatFrequency,
            photoUrl: meta.photoUrl,
          );

          await Supabase.instance.client
              .from('schedule')
              .update({'notes': newNotes})
              .eq('schedule_id', med.scheduleId!);
        }
      }

      // Cancel all pending follow-up reminders and snooze
      cancelMedicationReminder(med.id);
      await _notifPlugin.cancel(med.id.hashCode);
      for (int i = 0; i <= 5; i++) {
        await _notifPlugin.cancel(
          med.id.hashCode.abs() % 100000 + (i % 5) * 100000 + 1,
        );
      }

      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Set<String> get _takenTodayIds {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return _actualTodayLogs
        .where((l) => l.status == 'taken' && l.loggedAt.isAfter(todayStart))
        .map((l) => l.medicationId)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      color: _kPrimary,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 160),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            SizedBox(height: 16),
            if (_loading)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: _kPrimary),
                ),
              )
            else ...[
              _buildTodaySection(),
              SizedBox(height: 28),
              _buildLogSection(),
            ],
          ],
        ),
      ),
    );

    if (widget.isStandalone) {
      return Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: _kTextDark),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Medication'.tr(),
            style: TextStyle(
              fontFamily: 'League Spartan',
              fontWeight: FontWeight.w900,
              color: _kTextDark,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
        ),
        body: body,
      );
    }
    return body;
  }

  // ─── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Medication'.tr(),
                style: TextStyle(
                  fontFamily: 'League Spartan',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _kTextDark,
                ),
              ),
              Text(
                DateFormat('EEEE, d MMMM').format(now),
                style: const TextStyle(fontSize: 16, color: _kTextGrey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Today Section ─────────────────────────────────────────────────────────
  Widget _buildTodaySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Today's Medicine".tr(),
                style: TextStyle(
                  fontFamily: 'League Spartan',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _kTextDark,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ManageMedicineScreen(elderlyId: widget.elderlyId),
                  ),
                ).then((_) => _load()),
                child: Text(
                  'View All'.tr(),
                  style: TextStyle(
                    fontSize: 16,
                    color: _kPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),

          if (_expiredMeds.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Expired Medication Warning'.tr(),
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${'Do not consume:'.tr()} ${_expiredMeds.map((e) => e.name).join(', ')}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_medications.isEmpty)
            _buildNoMedicineCard()
          else ...[
            ...SessionManager().sessions.map((session) {
              final grouped = _groupedMeds;
              final medsForSession = grouped[session.name] ?? [];
              final fallback = grouped[session.id] ?? [];
              final fallbackLower = grouped[session.name.toLowerCase()] ?? [];
              final allMeds = {
                ...medsForSession,
                ...fallback,
                ...fallbackLower,
              }.toList();

              if (allMeds.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.wb_sunny_outlined,
                          size: 20,
                          color: _kBlue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${session.name} Session (${session.time.hour.toString().padLeft(2, '0')}:${session.time.minute.toString().padLeft(2, '0')})'
                              .tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _kBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...allMeds.map((med) => _buildMedicineCard(med)),
                ],
              );
            }),

            Builder(
              builder: (ctx) {
                final manager = SessionManager();
                final grouped = _groupedMeds;
                final knownSessions =
                    manager.sessions.map((s) => s.name).toSet()
                      ..addAll(manager.sessions.map((s) => s.id))
                      ..addAll(
                        manager.sessions.map((s) => s.name.toLowerCase()),
                      );

                final otherKeys = grouped.keys
                    .where((k) => !knownSessions.contains(k))
                    .toList();
                if (otherKeys.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: otherKeys.map((k) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 8.0,
                            bottom: 12.0,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.more_time_rounded,
                                size: 20,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                k.tr(),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...grouped[k]!.map((med) => _buildMedicineCard(med)),
                      ],
                    );
                  }).toList(),
                );
              },
            ),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AddEditMedicineScreen(elderlyId: widget.elderlyId),
                  ),
                ).then((_) => _load()),
                icon: const Icon(Icons.add, size: 20),
                label: Text(
                  'Add Medicine'.tr(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoMedicineCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.medication_outlined,
            size: 56,
            color: Colors.grey.shade300,
          ),
          SizedBox(height: 12),
          Text(
            'No medicines added'.tr(),
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tap "Manage" to add your medications'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ManageMedicineScreen(elderlyId: widget.elderlyId),
              ),
            ).then((_) => _load()),
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              'Add Medicine'.tr(),
              style: const TextStyle(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineCard(Medication med) {
    final taken = _takenTodayIds.contains(med.id);

    final today = DateTime.now();
    final todayStr = DateTime(today.year, today.month, today.day);
    final isExpired =
        med.expirationDate != null && med.expirationDate!.isBefore(todayStr);
    final isAlmostExpired =
        !isExpired &&
        med.expirationDate != null &&
        med.expirationDate!.difference(todayStr).inDays <= 7;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MedicineDetailScreen(
            medication: med,
            elderlyId: widget.elderlyId,
          ),
        ),
      ).then((_) => _load()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isExpired
              ? Colors.red.shade50
              : (isAlmostExpired ? Colors.orange.shade50 : _kCard),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpired
                ? Colors.red.shade300
                : (isAlmostExpired
                      ? Colors.orange.shade300
                      : (taken
                            ? _kPrimary.withOpacity(0.3)
                            : Colors.grey.shade200)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isExpired || isAlmostExpired)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isExpired ? Colors.red : Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isExpired
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      (isExpired ? 'EXPIRED MEDICINE' : 'ALMOST EXPIRED').tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _kBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: med.photo != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildMedPhoto(med.photo!, fit: BoxFit.cover),
                        )
                      : const Icon(
                          Icons.medication_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _kTextDark,
                        ),
                      ),
                      if (med.dosage != null)
                        Text(
                          med.dosage!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: _kTextGrey,
                          ),
                        ),
                    ],
                  ),
                ),
                if (taken)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Taken ✓'.tr(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            if (med.instruction != null || med.whenToTake != null) ...[
              const Divider(height: 20),
              Row(
                children: [
                  if (med.whenToTake != null) ...[
                    Icon(
                      Icons.schedule_rounded,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                    SizedBox(width: 4),
                    Text(
                      _formatWhenToTake(med.whenToTake, context),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    SizedBox(width: 14),
                  ],
                  if (med.instruction != null) ...[
                    Icon(
                      Icons.restaurant_rounded,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                    SizedBox(width: 4),
                    Text(
                      med.instruction!,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (!taken) ...[
              SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (isExpired) {
                          await NotificationDialogs.showExpiredAlert(
                            context,
                            medName: med.name,
                          );
                          return;
                        } else if (isAlmostExpired) {
                          final bool?
                          proceed = await NotificationDialogs.showAllergyAlert(
                            context,
                            title: 'Expiration Alert',
                            description:
                                '${med.name} will expire soon. Do you still want to take it?',
                          );
                          if (proceed != true) return;
                        }
                        _markTaken(med);
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: Text(
                        'I have taken'.tr(),
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MedicineDetailScreen(
                            medication: med,
                            elderlyId: widget.elderlyId,
                          ),
                        ),
                      ).then((_) => _load()),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(
                        'Details'.tr(),
                        style: const TextStyle(color: _kTextGrey, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Log Section ───────────────────────────────────────────────────────────
  Widget _buildLogSection() {
    final takenLogs = _selectedDateLogs
        .where((l) => l.status == 'taken')
        .toList();
    final takenMedIds = takenLogs.map((l) => l.medicationId).toSet();
    final missedLogs = _selectedDateLogs
        .where(
          (l) => l.status == 'missed' && !takenMedIds.contains(l.medicationId),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Medication Log'.tr(),
            style: const TextStyle(
              fontFamily: 'League Spartan',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _kTextDark,
            ),
          ),
        ),
        SizedBox(height: 14),

        // Date selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: _kTextDark),
                onPressed: () {
                  setState(
                    () => _selectedLogDate = _selectedLogDate.subtract(
                      const Duration(days: 1),
                    ),
                  );
                  _load();
                },
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedLogDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2050),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: _kPrimary,
                              onPrimary: Colors.white,
                              onSurface: _kTextDark,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (date != null) {
                      setState(() => _selectedLogDate = date);
                      _load();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.calendar_month,
                          size: 16,
                          color: _kPrimary,
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            DateFormat(
                              'EEEE, d MMM yyyy',
                            ).format(_selectedLogDate),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _kTextDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: _kTextDark),
                onPressed: () {
                  setState(
                    () => _selectedLogDate = _selectedLogDate.add(
                      const Duration(days: 1),
                    ),
                  );
                  _load();
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 20),

        if (_selectedDateLogs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              child: Text(
                'No logs for this period'.tr(),
                style: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          )
        else ...[
          if (missedLogs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Missed Doses'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE53935),
                ),
              ),
            ),
            SizedBox(height: 8),
            ...missedLogs.map((l) => _buildLogCard(l, isMissed: true)),
            SizedBox(height: 16),
          ],
          if (takenLogs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Taken Doses'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kPrimary,
                ),
              ),
            ),
            SizedBox(height: 8),
            ...takenLogs.map((l) => _buildLogCard(l, isMissed: false)),
          ],
        ],
      ],
    );
  }

  Widget _buildLogCard(MedicationLog log, {required bool isMissed}) {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMissed ? const Color(0xFFFFF0F0) : const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMissed ? Colors.red.shade100 : Colors.green.shade100,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isMissed
                      ? Colors.red.shade50
                      : _kPrimary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMissed ? Icons.close_rounded : Icons.check_rounded,
                  color: isMissed ? Colors.red : _kPrimary,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.medicationName ?? 'Medicine',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kTextDark,
                    ),
                  ),
                  if (!isMissed)
                    Text(
                      DateFormat('hh:mm a').format(log.loggedAt),
                      style: const TextStyle(fontSize: 14, color: _kTextGrey),
                    ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isMissed
                  ? Colors.red.shade100
                  : _kPrimary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isMissed ? 'Missed' : 'Taken',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isMissed ? Colors.red.shade700 : _kPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MANAGE MEDICINE SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class ManageMedicineScreen extends StatefulWidget {
  final String? elderlyId;
  const ManageMedicineScreen({super.key, this.elderlyId});
  @override
  State<ManageMedicineScreen> createState() => _ManageMedicineScreenState();
}

class _ManageMedicineScreenState extends State<ManageMedicineScreen> {
  // Deduplicated list — one entry per unique medication name
  List<Medication> _medications = [];
  // Map: medication name -> all sessions it's assigned to
  Map<String, List<String>> _medSessions = {};
  // Map: medication name -> all medication IDs (for delete-all)
  Map<String, List<String>> _medIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid =
          widget.elderlyId ?? Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final schedRes = await Supabase.instance.client
          .from('schedule')
          .select('schedule_id')
          .eq('elderly_id', uid);
      final ids = (schedRes as List)
          .map((s) => s['schedule_id']?.toString() ?? '')
          .toList();
      List<Medication> allMeds = [];
      if (ids.isNotEmpty) {
        final medRes = await Supabase.instance.client
            .from('medications')
            .select()
            .inFilter('schedule_id', ids);
        allMeds = (medRes as List)
            .map((m) => Medication.fromMap(m as Map<String, dynamic>))
            .toList();
      }

      // Group by medication name — deduplicate for display
      final Map<String, Medication> uniqueByName = {};
      final Map<String, List<String>> sessionsMap = {};
      final Map<String, List<String>> idsMap = {};
      for (final med in allMeds) {
        final key = med.name.trim().toLowerCase();
        uniqueByName.putIfAbsent(key, () => med);
        sessionsMap.putIfAbsent(key, () => []);
        idsMap.putIfAbsent(key, () => []);
        final session = med.whenToTake;
        if (session != null &&
            session.isNotEmpty &&
            !sessionsMap[key]!.contains(session)) {
          sessionsMap[key]!.add(session);
        }
        idsMap[key]!.add(med.id);
      }

      if (mounted) {
        setState(() {
          _medications = uniqueByName.values.toList();
          _medSessions = {for (final e in sessionsMap.entries) e.key: e.value};
          _medIds = {for (final e in idsMap.entries) e.key: e.value};
          _loading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('ManageMedicine _load Error: $e\n$stack');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading meds: $e')));
      }
    }
  }

  Future<void> _delete(Medication med) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete Medicine'.tr()),
        content: Text('Delete "${med.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete'.tr(), style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      // Delete ALL session records for this medicine name
      final key = med.name.trim().toLowerCase();
      final idsToDelete = _medIds[key] ?? [med.id];
      for (final id in idsToDelete) {
        // Find and delete the linked schedule if any
        final targetMed = _medications.firstWhere(
          (m) => m.id == id,
          orElse: () => med,
        );
        if (targetMed.scheduleId != null) {
          try {
            await Supabase.instance.client
                .from('schedule')
                .delete()
                .eq('schedule_id', targetMed.scheduleId!);
          } catch (e) {
            debugPrint('Error deleting linked schedule: $e');
          }
        }
        await Supabase.instance.client
            .from('medications')
            .delete()
            .eq('medication_id', id);
      }
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Manage Medicine'.tr(),
          style: TextStyle(
            fontFamily: 'League Spartan',
            fontWeight: FontWeight.w900,
            color: _kTextDark,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _kPrimary))
          : RefreshIndicator(
              color: _kPrimary,
              onRefresh: _load,
              child: _medications.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(height: 80),
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.medication_outlined,
                                size: 72,
                                color: Colors.grey.shade300,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No medicines yet'.tr(),
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Tap + to add your first medicine'.tr(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _medications.length,
                      itemBuilder: (_, i) => _buildMedCard(_medications[i]),
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddEditMedicineScreen()),
        ).then((_) => _load()),
        backgroundColor: _kPrimary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Add Medicine'.tr(),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildMedCard(Medication med) {
    bool isAlmostExpired = false;
    bool isExpired = false;
    if (med.expirationDate != null) {
      final diff = med.expirationDate!.difference(DateTime.now()).inDays;
      if (diff < 0) {
        isExpired = true;
      } else if (diff <= 7) {
        isAlmostExpired = true;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MedicineDetailScreen(medication: med),
              ),
            ).then((_) => _load()),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _kBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: med.photo != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildMedPhoto(med.photo!, fit: BoxFit.cover),
                        )
                      : const Icon(
                          Icons.medication_rounded,
                          color: _kBlue,
                          size: 26,
                        ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _kTextDark,
                        ),
                      ),
                      if (med.dosage != null)
                        Text(
                          med.dosage!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: _kTextGrey,
                          ),
                        ),
                      // Show all sessions as chips
                      Builder(
                        builder: (ctx) {
                          final key = med.name.trim().toLowerCase();
                          final sessions = _medSessions[key] ?? [];
                          if (sessions.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: sessions
                                  .map(
                                    (s) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _kBlue.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: _kBlue.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: Text(
                                        _formatWhenToTake(s, ctx),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _kBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (med.stock != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (med.stock! < 5 ? Colors.red : _kPrimary)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${med.stock} ${med.stockUnit ?? "left"}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: med.stock! < 5 ? Colors.red : _kPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isExpired || isAlmostExpired) ...[
            SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isExpired ? Colors.red.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isExpired
                      ? Colors.red.shade200
                      : Colors.orange.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isExpired
                        ? Icons.error_outline
                        : Icons.warning_amber_rounded,
                    size: 16,
                    color: isExpired
                        ? Colors.red.shade700
                        : Colors.orange.shade700,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isExpired
                          ? 'This medicine expired on ${DateFormat('MMM d, yyyy').format(med.expirationDate!)}!'
                          : 'This medicine will expire soon (${DateFormat('MMM d, yyyy').format(med.expirationDate!)})',
                      style: TextStyle(
                        fontSize: 12,
                        color: isExpired
                            ? Colors.red.shade700
                            : Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 24, thickness: 1),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddEditMedicineScreen(
                        existing: med,
                        elderlyId: widget.elderlyId,
                      ),
                    ),
                  ).then((_) => _load()),
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: _kBlue,
                  ),
                  label: Text(
                    'Edit'.tr(),
                    style: TextStyle(
                      color: _kBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _kBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _delete(med),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: Colors.red,
                  ),
                  label: Text(
                    'Delete'.tr(),
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ADD / EDIT MEDICINE SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class AddEditMedicineScreen extends StatefulWidget {
  final Medication? existing;
  final String? elderlyId;
  const AddEditMedicineScreen({super.key, this.existing, this.elderlyId});
  @override
  State<AddEditMedicineScreen> createState() => _AddEditMedicineScreenState();
}

class _AddEditMedicineScreenState extends State<AddEditMedicineScreen> {
  final _nameCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _minIntervalCtrl = TextEditingController(text: '4');
  String? _unit = 'tablet(s)';
  String? _stockUnit = 'tablet(s)';
  String? _whenToTake;
  String? _instruction;
  DateTime? _expirationDate;
  final Set<String> _selectedWhenToTakes = {};
  TimeOfDay? _reminderTime;
  final bool _isLoadingMap = false;
  bool _saving = false;
  bool _checkingAllergy = false;
  File? _selectedImage;
  String? _existingPhotoUrl;

  static const _units = [
    'tablet(s)',
    'pill(s)',
    'capsule(s)',
    'ml',
    'mg',
    'drops',
    'application(s)',
    'injection(s)',
  ];

  static const _whenToTakes = [
    'Morning',
    'Afternoon',
    'Evening',
    'Night',
    'As needed',
    'Custom',
  ];
  static const _instructions = [
    'Before meal',
    'After meal',
    'With meal',
    'Before sleep',
    'With water',
    'As directed',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      if (e.dosage != null) {
        final parts = e.dosage!.split(' ');
        if (parts.length > 1) {
          _dosageCtrl.text = parts[0];
          final maybeUnit = parts.sublist(1).join(' ');
          if (_units.contains(maybeUnit)) {
            _unit = maybeUnit;
            _stockUnit = maybeUnit;
          } else {
            _dosageCtrl.text = e.dosage!;
            _unit = 'tablet(s)';
            _stockUnit = 'tablet(s)';
          }
        } else {
          _dosageCtrl.text = e.dosage!;
        }
      }
      _stockCtrl.text = e.stock?.toString() ?? '';
      _notesCtrl.text = e.notes ?? '';
      _minIntervalCtrl.text = e.minIntervalHours.toString();
      _whenToTake = e.whenToTake;
      _instruction = e.instruction;
      _expirationDate = e.expirationDate;
      _existingPhotoUrl = e.photo;

      if (_whenToTake != null) {
        if (_whenToTake!.contains(':')) {
          try {
            final parts = _whenToTake!.split(':');
            _reminderTime = TimeOfDay(
              hour: int.parse(parts[0]),
              minute: int.parse(parts[1]),
            );
            _whenToTake = 'Custom';
          } catch (_) {}
        } else {
          if (_whenToTake == 'Morning') {
            _reminderTime = const TimeOfDay(hour: 8, minute: 0);
          } else if (_whenToTake == 'Afternoon') {
            _reminderTime = const TimeOfDay(hour: 12, minute: 0);
          } else if (_whenToTake == 'Evening') {
            _reminderTime = const TimeOfDay(hour: 18, minute: 0);
          } else if (_whenToTake == 'Night') {
            _reminderTime = const TimeOfDay(hour: 23, minute: 49);
          }
        }
        _selectedWhenToTakes.add(_whenToTake!);
      }
    } else {
      _selectedWhenToTakes.add('Morning');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _stockCtrl.dispose();
    _notesCtrl.dispose();
    _minIntervalCtrl.dispose();
    super.dispose();
  }

  // ─── Allergy check via web search ─────────────────────────────────────────
  Future<void> _checkAllergy() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Enter medicine name first'.tr())));
      return;
    }
    setState(() {
      _checkingAllergy = true;
    });

    // Get user's allergy info from the database
    String? userAllergies;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        // Fetch specific allergies from the new allergy_list table
        final res = await Supabase.instance.client
            .from('allergy_list')
            .select('allergy(name)')
            .eq('elderly_id', uid);

        final List<String> fetchedAllergies = [];
        for (var row in (res as List)) {
          final allergyData = row['allergy'];
          if (allergyData != null && allergyData['name'] != null) {
            fetchedAllergies.add(allergyData['name'] as String);
          }
        }
        if (fetchedAllergies.isNotEmpty) {
          userAllergies = fetchedAllergies.join(', ');
        }
      }
    } catch (e) {
      debugPrint('Error fetching allergies: $e');
    }

    if (mounted) {
      setState(() {
        _checkingAllergy = false;
      });
      _showAllergySheet(name, userAllergies);
    }
  }

  void _showAllergySheet(String medicineName, String? userAllergies) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AllergyAlertSheet(
        medicineName: medicineName,
        userAllergies: userAllergies,
      ),
    );
  }

  Future<void> _delete() async {
    final med = widget.existing;
    if (med == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Medicine'.tr()),
        content: Text('Delete "${med.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete'.tr(), style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() => _saving = true);
      try {
        final uid = widget.elderlyId ?? Supabase.instance.client.auth.currentUser?.id;
        bool deletedAll = false;
        
        if (uid != null) {
          final schedRes = await Supabase.instance.client
              .from('schedule')
              .select('schedule_id')
              .eq('elderly_id', uid);
          final ids = (schedRes as List).map((s) => s['schedule_id']?.toString() ?? '').toList();
          
          if (ids.isNotEmpty) {
            final medRes = await Supabase.instance.client
                .from('medications')
                .select('medication_id, schedule_id')
                .eq('medication_name', med.name)
                .inFilter('schedule_id', ids);
                
            for (final m in medRes as List) {
              final mId = m['medication_id'];
              final sId = m['schedule_id'];
              if (sId != null) {
                try {
                  await Supabase.instance.client.from('schedule').delete().eq('schedule_id', sId);
                } catch (e) {
                  debugPrint('Error deleting linked schedule: $e');
                }
              }
              cancelMedicationReminder(mId);
              await Supabase.instance.client.from('medications').delete().eq('medication_id', mId);
            }
            deletedAll = true;
          }
        }
        
        if (!deletedAll) {
          if (med.scheduleId != null) {
            try {
              await Supabase.instance.client
                  .from('schedule')
                  .delete()
                  .eq('schedule_id', med.scheduleId!);
            } catch (e) {
              debugPrint('Error deleting linked schedule: $e');
            }
          }
          cancelMedicationReminder(med.id); // stop Dart timer immediately
          await Supabase.instance.client
              .from('medications')
              .delete()
              .eq('medication_id', med.id);
        }
        await syncAllMedicationReminders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Medicine deleted successfully'.tr())),
          );
          Navigator.pop(context, 'deleted');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Medicine name is required'.tr())));
      return;
    }
    setState(() => _saving = true);
    try {
      final uid =
          widget.elderlyId ?? Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in');

      final elderlyRes = await Supabase.instance.client
          .from('elderly')
          .select('user_id')
          .eq('user_id', uid)
          .limit(1)
          .maybeSingle();

      if (elderlyRes == null) {
        await Supabase.instance.client.from('elderly').insert({'user_id': uid});
      }

      String finalNotes = ScheduleMetadata.toNotesString(
        notesText: _notesCtrl.text.trim(),
        type: 'Medication',
        priority: 'medium',
        status: 'pending',
        allDay: false,
        endDateTime: null,
        reminderTime: null,
        repeat: 'Daily',
        photoUrl: null,
      );

      final timesToSave = _selectedWhenToTakes.isEmpty
          ? ['As needed']
          : _selectedWhenToTakes.toList();

      bool isFirstUpdate = true;
      int minInterval = int.tryParse(_minIntervalCtrl.text.trim()) ?? 4;
      for (String timeToTake in timesToSave) {
        String? whenToTakeValue = timeToTake;
        TimeOfDay? currentReminderTime = _reminderTime;

        if (whenToTakeValue == 'Custom' && _reminderTime != null) {
          final hStr = _reminderTime!.hour.toString().padLeft(2, '0');
          final mStr = _reminderTime!.minute.toString().padLeft(2, '0');
          whenToTakeValue = '$hStr:$mStr';
        } else if (whenToTakeValue == 'Morning') {
          currentReminderTime = const TimeOfDay(hour: 8, minute: 0);
        } else if (whenToTakeValue == 'Afternoon') {
          currentReminderTime = const TimeOfDay(hour: 12, minute: 0);
        } else if (whenToTakeValue == 'Evening') {
          currentReminderTime = const TimeOfDay(hour: 18, minute: 0);
        } else if (whenToTakeValue == 'Night') {
          currentReminderTime = const TimeOfDay(hour: 23, minute: 49);
        } else if (whenToTakeValue == 'As needed') {
          currentReminderTime = null;
        }

        // Prevent double scheduling the SAME medicine at the same time
        if (whenToTakeValue != 'As needed') {
          final checkSchedRes = await Supabase.instance.client
              .from('schedule')
              .select('schedule_id')
              .eq('elderly_id', uid);

          final elderlySchedIds = (checkSchedRes as List)
              .map((s) => s['schedule_id'])
              .toList();

          if (elderlySchedIds.isNotEmpty) {
            final currentMedsRes = await Supabase.instance.client
                .from('medications')
                .select('when_to_take, medication_id, medication_name')
                .inFilter('schedule_id', elderlySchedIds);

            for (final m in currentMedsRes as List) {
              final existingName = m['medication_name']
                  ?.toString()
                  .toLowerCase()
                  .trim();
              final newName = name.toLowerCase().trim();

              if (m['medication_id'] != widget.existing?.id &&
                  m['when_to_take'] == whenToTakeValue &&
                  existingName == newName) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'You already have $name scheduled at this exact time!',
                      ),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                  setState(() => _saving = false);
                }
                return;
              }
            }
          }
        }

        final now = DateTime.now();
        DateTime scheduleDateTime;
        if (currentReminderTime != null) {
          scheduleDateTime = DateTime(
            now.year,
            now.month,
            now.day,
            currentReminderTime.hour,
            currentReminderTime.minute,
          );
        } else {
          scheduleDateTime = DateTime(now.year, now.month, now.day, 8, 0);
        }

        final scheduleRow = {
          'elderly_id': uid,
          'title': 'Take $name',
          'schedule_date_time': scheduleDateTime.toUtc().toIso8601String(),
          'location': 'Home',
          'notes': finalNotes,
        };

        String scheduleId;
        if (widget.existing?.scheduleId != null) {
          scheduleId = widget.existing!.scheduleId!;
          await Supabase.instance.client
              .from('schedule')
              .update(scheduleRow)
              .eq('schedule_id', scheduleId);
        } else {
          final newSched = await Supabase.instance.client
              .from('schedule')
              .insert(scheduleRow)
              .select('schedule_id')
              .single();
          scheduleId = newSched['schedule_id'] as String;
        }

        final data = {
          'medication_name': name,
          if (_dosageCtrl.text.trim().isNotEmpty)
            'dosage': '${_dosageCtrl.text.trim()} ${_unit ?? ""}'.trim(),
          'when_to_take': whenToTakeValue,
          if (_instruction != null) 'instruction': _instruction,
          if (_stockCtrl.text.trim().isNotEmpty)
            'medication_stock': int.tryParse(_stockCtrl.text.trim()),
          if (_notesCtrl.text.trim().isNotEmpty || _stockUnit != null)
            'medical_notes':
                '${_notesCtrl.text.trim()}${_stockUnit != null ? '|stock_unit:$_stockUnit' : ''}',
          if (_expirationDate != null)
            'expiration_date': _expirationDate!
                .toIso8601String()
                .split('T')
                .first,
          'schedule_id': scheduleId,
          'min_interval_hours': minInterval,
        };

        if (_selectedImage != null) {
          try {
            final bytes = await _selectedImage!.readAsBytes();
            final base64Str = base64Encode(bytes);
            final ext = _selectedImage!.path.split('.').last.toLowerCase();
            final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
            final url = 'data:$mimeType;base64,$base64Str';

            data['photo'] = url;
            finalNotes = ScheduleMetadata.toNotesString(
              notesText: _notesCtrl.text.trim(),
              type: 'Medication',
              priority: 'medium',
              status: 'pending',
              allDay: false,
              endDateTime: null,
              reminderTime: null,
              repeat: 'Daily',
              photoUrl: url,
            );
            await Supabase.instance.client
                .from('schedule')
                .update({'notes': finalNotes})
                .eq('schedule_id', scheduleId);
          } catch (e) {
            debugPrint('Failed to upload photo: $e');
          }
        } else if (_existingPhotoUrl != null) {
          data['photo'] = _existingPhotoUrl;
          finalNotes = ScheduleMetadata.toNotesString(
            notesText: _notesCtrl.text.trim(),
            type: 'Medication',
            priority: 'medium',
            status: 'pending',
            allDay: false,
            endDateTime: null,
            reminderTime: null,
            repeat: 'Daily',
            photoUrl: _existingPhotoUrl,
          );
          await Supabase.instance.client
              .from('schedule')
              .update({'notes': finalNotes})
              .eq('schedule_id', scheduleId);
        }

        if (widget.existing != null && isFirstUpdate) {
          await Supabase.instance.client
              .from('medications')
              .update(data)
              .eq('medication_id', widget.existing!.id);
          isFirstUpdate = false;
        } else {
          await Supabase.instance.client.from('medications').insert(data);
        }
      } // End of timesToSave loop

      await syncAllMedicationReminders();

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEdit ? 'Edit Medicine' : 'Add Medicine',
          style: const TextStyle(
            fontFamily: 'League Spartan',
            fontWeight: FontWeight.w900,
            color: _kTextDark,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Medicine name + allergy check
            _label('Medicine Name *'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: _inputDeco('e.g. Paracetamol'),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                SizedBox(width: 10),
                GestureDetector(
                  onTap: _checkingAllergy ? null : _checkAllergy,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: _checkingAllergy
                        ? Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.orange,
                            ),
                          )
                        : const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                            size: 24,
                          ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              'Tap ⚠️ to check allergy info'.tr(),
              style: TextStyle(fontSize: 11, color: Colors.orange.shade600),
            ),
            SizedBox(height: 16),

            _label('Photo'),
            GestureDetector(
              onTap: () async {
                final picker = ImagePicker();
                final xfile = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (xfile != null) {
                  setState(() {
                    _selectedImage = File(xfile.path);
                  });
                }
              },
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _selectedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(_selectedImage!, fit: BoxFit.cover),
                      )
                    : (_existingPhotoUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _buildMedPhoto(
                                _existingPhotoUrl!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_a_photo,
                                  color: _kTextGrey,
                                  size: 32,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Tap to add photo',
                                  style: TextStyle(color: _kTextGrey),
                                ),
                              ],
                            )),
              ),
            ),
            if (_selectedImage != null || _existingPhotoUrl != null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedImage = null;
                    _existingPhotoUrl = null;
                  });
                },
                child: Text(
                  'Remove Photo',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            SizedBox(height: 16),

            _label('Dosage (Amount & Unit)'),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _dosageCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDeco('e.g. 1'),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _dropdown(
                    'Unit',
                    _units,
                    _unit,
                    (v) => setState(() => _unit = v),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            _label('When to take'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _whenToTakes.map((t) {
                final isSelected = _selectedWhenToTakes.contains(t);
                return FilterChip(
                  label: Text(t),
                  selected: isSelected,
                  selectedColor: _kPrimary.withOpacity(0.2),
                  checkmarkColor: _kPrimary,
                  onSelected: (val) {
                    setState(() {
                      if (t == 'Custom' || t == 'As needed') {
                        if (val) {
                          _selectedWhenToTakes.clear();
                          _selectedWhenToTakes.add(t);
                          if (t == 'As needed') _reminderTime = null;
                        } else {
                          _selectedWhenToTakes.remove(t);
                        }
                      } else {
                        if (val) {
                          _selectedWhenToTakes.remove('Custom');
                          _selectedWhenToTakes.remove('As needed');
                          _selectedWhenToTakes.add(t);
                        } else {
                          _selectedWhenToTakes.remove(t);
                        }
                      }
                    });
                  },
                );
              }).toList(),
            ),
            SizedBox(height: 16),

            if (_selectedWhenToTakes.contains('Custom')) ...[
              _label('Reminder Time'),
              GestureDetector(
                onTap: () async {
                  final initialTime =
                      _reminderTime ?? const TimeOfDay(hour: 8, minute: 0);
                  final time = await showTimePicker(
                    context: context,
                    initialTime: initialTime,
                  );
                  if (time != null) {
                    setState(() {
                      _reminderTime = time;
                      _whenToTake = 'Custom';
                      if (!isEdit) {
                        _selectedWhenToTakes.clear();
                        _selectedWhenToTakes.add('Custom');
                      }
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _reminderTime == null
                            ? 'Select Reminder Time'
                            : _reminderTime!.format(context),
                        style: TextStyle(
                          fontSize: 16,
                          color: _reminderTime == null
                              ? Colors.grey.shade400
                              : _kTextDark,
                        ),
                      ),
                      const Icon(
                        Icons.access_time,
                        size: 18,
                        color: _kTextGrey,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
            ],

            _label('Instruction'),
            _dropdown(
              'Select instruction',
              _instructions,
              _instruction,
              (v) => setState(() => _instruction = v),
            ),
            SizedBox(height: 16),

            _label('Minimum Interval Between Doses (Hours)'),
            TextField(
              controller: _minIntervalCtrl,
              keyboardType: TextInputType.number,
              decoration: _inputDeco('e.g. 4'),
            ),
            SizedBox(height: 16),

            _label('Stock'),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _stockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDeco('e.g. 30'),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: _dropdown(
                    'Unit',
                    _units,
                    _stockUnit,
                    (v) => setState(() => _stockUnit = v),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            _label('Medical Notes'),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: _inputDeco('Any notes about this medicine...'),
            ),
            SizedBox(height: 16),

            _label('Expiration Date'),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _expirationDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _expirationDate = d);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _expirationDate == null
                          ? 'Select Date'
                          : DateFormat('dd MMM yyyy').format(_expirationDate!),
                      style: TextStyle(
                        fontSize: 16,
                        color: _expirationDate == null
                            ? Colors.grey.shade400
                            : _kTextDark,
                      ),
                    ),
                    const Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: _kTextGrey,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _saving
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    : Text(
                        isEdit ? 'Update Medicine' : 'Save Medicine',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            if (isEdit) ...[
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: Text(
                    'Delete Medicine'.tr(),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: const TextStyle(
        fontFamily: 'Open Sans',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _kTextGrey,
      ),
    ),
  );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _kPrimary, width: 1.5),
    ),
    filled: true,
    fillColor: Colors.white,
  );

  Widget _dropdown(
    String hint,
    List<String> items,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      hint: Text(
        hint,
        style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      ),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kPrimary, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      items: items
          .map((i) => DropdownMenuItem(value: i, child: Text(i)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MEDICINE DETAIL SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class MedicineDetailScreen extends StatefulWidget {
  final Medication medication;
  final String? elderlyId;
  const MedicineDetailScreen({
    super.key,
    required this.medication,
    this.elderlyId,
  });

  @override
  State<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen> {
  late Medication _medication;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _medication = widget.medication;
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('medications')
          .select()
          .eq('medication_id', _medication.id)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _medication = Medication.fromMap(res);
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Medicine'.tr()),
        content: Text('Delete "${_medication.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete'.tr(), style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        final uid = widget.elderlyId ?? Supabase.instance.client.auth.currentUser?.id;
        bool deletedAll = false;
        
        if (uid != null) {
          final schedRes = await Supabase.instance.client
              .from('schedule')
              .select('schedule_id')
              .eq('elderly_id', uid);
          final ids = (schedRes as List).map((s) => s['schedule_id']?.toString() ?? '').toList();
          
          if (ids.isNotEmpty) {
            final medRes = await Supabase.instance.client
                .from('medications')
                .select('medication_id, schedule_id')
                .eq('medication_name', _medication.name)
                .inFilter('schedule_id', ids);
                
            for (final m in medRes as List) {
              final mId = m['medication_id'];
              final sId = m['schedule_id'];
              if (sId != null) {
                try {
                  await Supabase.instance.client.from('schedule').delete().eq('schedule_id', sId);
                } catch (_) {}
              }
              cancelMedicationReminder(mId);
              await Supabase.instance.client.from('medications').delete().eq('medication_id', mId);
            }
            deletedAll = true;
          }
        }
        
        if (!deletedAll) {
          if (_medication.scheduleId != null) {
            try {
              await Supabase.instance.client
                  .from('schedule')
                  .delete()
                  .eq('schedule_id', _medication.scheduleId!);
            } catch (_) {}
          }
          cancelMedicationReminder(_medication.id);
          await Supabase.instance.client
              .from('medications')
              .delete()
              .eq('medication_id', _medication.id);
        }
        await syncAllMedicationReminders();
        if (mounted) {
          final ctx = context;
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text('Medicine deleted successfully'.tr())),
          );
          Navigator.pop(ctx, true);
        }
      } catch (e) {
        if (mounted) {
          final ctx = context;
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = _medication;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Medicine Details'.tr(),
          style: TextStyle(
            fontFamily: 'League Spartan',
            fontWeight: FontWeight.w900,
            color: _kTextDark,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: _kBlue),
            onPressed: () =>
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddEditMedicineScreen(
                      existing: med,
                      elderlyId: widget.elderlyId,
                    ),
                  ),
                ).then((val) {
                  if (val == 'deleted') {
                    Navigator.pop(context, true);
                  } else {
                    _refresh();
                  }
                }),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _kPrimary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Hero card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kBlue, Color(0xFF1A78C2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        med.photo != null
                            ? GestureDetector(
                                onTap: () => showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    backgroundColor: Colors.transparent,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        InteractiveViewer(
                                          child: _buildMedPhoto(med.photo!),
                                        ),
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 30,
                                            ),
                                            onPressed: () =>
                                                Navigator.pop(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: _buildMedPhoto(
                                    med.photo!,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              )
                            : Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.medication_rounded,
                                  color: Colors.white,
                                  size: 42,
                                ),
                              ),
                        SizedBox(height: 16),
                        Text(
                          med.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (med.dosage != null)
                          Text(
                            med.dosage!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                      ],
                    ),
                  ),

                  SizedBox(height: 20),

                  // Details card
                  _infoCard([
                    _infoRow(
                      Icons.schedule_rounded,
                      'When to take',
                      _formatWhenToTake(med.whenToTake, context),
                    ),
                    _infoRow(
                      Icons.restaurant_rounded,
                      'Instruction',
                      med.instruction ?? 'Not specified',
                    ),
                    _infoRow(
                      Icons.inventory_2_rounded,
                      'Stock',
                      med.stock != null
                          ? '${med.stock} ${med.stockUnit ?? "remaining"}'
                          : 'Not tracked',
                    ),
                    if (med.expirationDate != null)
                      _infoRow(
                        Icons.event_busy_rounded,
                        'Expires',
                        DateFormat('dd MMM yyyy').format(med.expirationDate!),
                      ),
                    if (med.notes?.isNotEmpty == true)
                      _infoRow(Icons.notes_rounded, 'Notes', med.notes!),
                  ]),

                  SizedBox(height: 16),

                  // Stock warning
                  if (med.stock != null && med.stock! < 5)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_rounded,
                            color: Colors.red,
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Low stock! Only ${med.stock} ${med.stockUnit ?? "tablet(s)"} remaining. Please refill soon.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  SizedBox(height: 16),

                  // Check allergy button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(
                          'https://www.google.com/search?q=${Uri.encodeComponent('${med.name} allergy side effects')}',
                        );
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (e) {
                          debugPrint('Could not launch url: $e');
                        }
                      },
                      icon: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                      ),
                      label: Text(
                        'Check Allergy & Side Effects'.tr(),
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.orange),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _infoCard(List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: rows),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _kPrimary, size: 18),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _kTextGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kTextDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ALLERGY ALERT BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════
class AllergyAlertSheet extends StatelessWidget {
  final String medicineName;
  final String? userAllergies;

  const AllergyAlertSheet({
    super.key,
    required this.medicineName,
    this.userAllergies,
  });

  // Common allergy keywords — basic client-side check
  static const _knownAllergens = {
    'penicillin': ['amoxicillin', 'ampicillin', 'flucloxacillin'],
    'aspirin': ['ibuprofen', 'naproxen', 'diclofenac', 'mefenamic'],
    'sulfa': ['sulfamethoxazole', 'trimethoprim'],
    'codeine': ['morphine', 'tramadol', 'oxycodone'],
    'erythromycin': ['azithromycin', 'clarithromycin'],
  };

  bool get _hasPotentialConflict {
    if (userAllergies == null || userAllergies!.isEmpty) return false;
    final allergyLower = userAllergies!.toLowerCase();
    final medLower = medicineName.toLowerCase();
    // Direct match
    if (allergyLower.contains(medLower)) return true;
    // Class-based check
    for (final entry in _knownAllergens.entries) {
      if (allergyLower.contains(entry.key)) {
        if (entry.value.any((rel) => medLower.contains(rel))) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final conflict = _hasPotentialConflict;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: 20),

          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: conflict ? Colors.red.shade50 : Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              conflict ? Icons.warning_rounded : Icons.check_circle_rounded,
              color: conflict ? Colors.red : Colors.green,
              size: 48,
            ),
          ),
          SizedBox(height: 16),

          Text(
            conflict ? 'Potential Allergy Alert!' : 'No Known Conflicts',
            style: TextStyle(
              fontFamily: 'League Spartan',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: conflict ? Colors.red : Colors.green.shade700,
            ),
          ),
          SizedBox(height: 8),

          Text(
            medicineName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _kTextDark,
            ),
          ),
          SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: conflict ? Colors.red.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: conflict ? Colors.red.shade200 : Colors.green.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (userAllergies?.isNotEmpty == true) ...[
                  Text(
                    'Your recorded allergies:'.tr(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    userAllergies!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: conflict ? Colors.red.shade700 : _kTextDark,
                    ),
                  ),
                  SizedBox(height: 12),
                ],
                Text(
                  conflict
                      ? '⚠️ "$medicineName" may conflict with your known allergies. Please consult your doctor before taking this medicine.'
                      : '✅ No direct conflict found between "$medicineName" and your recorded allergies. Always consult your doctor if unsure.',
                  style: TextStyle(
                    fontSize: 13,
                    color: conflict
                        ? Colors.red.shade700
                        : Colors.green.shade800,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),

          // Web search for more info
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(
                  'https://www.google.com/search?q=${Uri.encodeComponent('$medicineName allergy information side effects')}',
                );
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  debugPrint('Could not launch url: $e');
                }
              },
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: Text('Search More Info Online'.tr()),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kBlue),
                foregroundColor: _kBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: conflict ? Colors.red : _kPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                conflict ? 'I Understand, Proceed with Caution' : 'Got it',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
