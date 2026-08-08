import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/medication_dose.dart';

class ReminderNotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  
  static const String channelId = 'medication_reminder_fsm_channel';
  static const String channelName = 'Medication Reminders';
  static const String channelDesc = 'FSM-based medication reminders';

  Function(String?)? onNotificationTap;

  Future<void> init({Function(String?)? onNotificationTap}) async {
    this.onNotificationTap = onNotificationTap;
    const android = AndroidInitializationSettings('ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onSelectNotification,
    );
  }

  void _onSelectNotification(NotificationResponse response) {
    if (onNotificationTap != null) {
      onNotificationTap!(response.payload);
    }
  }

  int _stringToInt(String s) {
    int hash = 0;
    for (int i = 0; i < s.length; i++) {
      hash = (31 * hash + s.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash % 100000;
  }

  // Pre-schedule multiple notifications for a dose to handle offline/background repetition
  Future<void> scheduleDoseReminders(MedicationDose dose) async {
    int baseId = _stringToInt(dose.id);
    
    // Calculate the sequence of reminders according to FSM rules
    // First hour: every 10 mins (0, 10, 20, 30, 40, 50)
    // After first hour: every 30 mins (60, 90, 120, ...) until windowEnd
    
    List<int> reminderOffsetsMins = [];
    for (int i = 0; i < 60; i += 10) {
      reminderOffsetsMins.add(i);
    }
    for (int i = 60; ; i += 30) {
      final scheduledTime = dose.scheduledTime.add(Duration(minutes: i));
      if (scheduledTime.isAfter(dose.windowEnd)) {
        break; // Stop scheduling if past window
      }
      reminderOffsetsMins.add(i);
    }
    
    final androidDetails = const AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.reminder,
    );
    final notificationDetails = NotificationDetails(android: androidDetails);
    
    for (int i = 0; i < reminderOffsetsMins.length; i++) {
      final delay = reminderOffsetsMins[i];
      final reminderTime = dose.scheduledTime.add(Duration(minutes: delay));
      
      // If reminderTime has already passed, don't schedule it
      if (reminderTime.isBefore(DateTime.now())) continue;
      
      await _plugin.zonedSchedule(
        baseId + i,
        '💊 Time to take ${dose.name}',
        '${dose.dosage ?? 'Take'} — ${dose.instruction ?? ''}',
        tz.TZDateTime.from(reminderTime, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: dose.id, // Pass dose ID in payload to open dialog on tap
      );
    }
  }

  // Cancel all pre-scheduled notifications for a dose
  Future<void> cancelDoseReminders(String doseId) async {
    int baseId = _stringToInt(doseId);
    // Cancel the first 50 possible notifications to be safe
    for (int i = 0; i < 50; i++) {
      await _plugin.cancel(baseId + i);
    }
  }
}
