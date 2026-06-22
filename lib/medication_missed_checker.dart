import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'schedule_dashboard_view.dart';
import 'medication_dashboard_view.dart';
import 'sos_notification_service.dart';

class MedicationMissedChecker {
  static Future<void> checkAndMarkMissed(String elderlyId) async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      
      // Look back at the past 3 days to catch any missed medications
      for (int i = 1; i <= 3; i++) {
        final targetDate = todayStart.subtract(Duration(days: i));
        
        final schedRes = await Supabase.instance.client
            .from('schedule')
            .select()
            .eq('elderly_id', elderlyId);
            
        final List<String> scheduleIds = [];
        for (var s in schedRes as List) {
          try {
            final record = ScheduleRecord.fromMap(s as Map<String, dynamic>);
            bool isTargetDate = false;
            
            final recordStart = DateTime(record.scheduleDateTime.year, record.scheduleDateTime.month, record.scheduleDateTime.day);
            if (targetDate.isBefore(recordStart)) continue;

            if (recordStart == targetDate) {
              isTargetDate = true;
            } else if (record.repeatFrequency == 'Daily') {
              isTargetDate = true;
            } else if (record.repeatFrequency == 'Weekly' && record.scheduleDateTime.weekday == targetDate.weekday) {
              isTargetDate = true;
            } else if (record.repeatFrequency == 'Monthly' && record.scheduleDateTime.day == targetDate.day) {
              isTargetDate = true;
            }
            if (isTargetDate) {
              scheduleIds.add(record.id);
            }
          } catch (e) {
            // ignore
          }
        }

        if (scheduleIds.isEmpty) continue;

        final medRes = await Supabase.instance.client
            .from('medications')
            .select()
            .inFilter('schedule_id', scheduleIds);
            
        final meds = (medRes as List).map((m) => Medication.fromMap(m as Map<String, dynamic>)).toList();
        if (meds.isEmpty) continue;

        final targetEnd = targetDate.add(const Duration(days: 1));
        final medIds = meds.map((m) => m.id).toList();
        
        final logRes = await Supabase.instance.client
            .from('medication_logs')
            .select()
            .inFilter('medication_id', medIds)
            .gte('logged_at', targetDate.toUtc().toIso8601String())
            .lt('logged_at', targetEnd.toUtc().toIso8601String());
            
        final loggedMedIds = (logRes as List).map((l) => l['medication_id'] as String).toSet();

        for (var med in meds) {
          if (!loggedMedIds.contains(med.id)) {
            // Check if missed log already exists? 
            // We queried ALL logs for this day, so if it's not in loggedMedIds, no log exists.
            await Supabase.instance.client.from('medication_logs').insert({
              'medication_id': med.id,
              'logged_at': targetDate.add(const Duration(hours: 23, minutes: 59)).toUtc().toIso8601String(),
              'status': 'missed',
            });
            
            // Note: The realtime database listener in CaregiverDashboard will pick this up and send a notification.
          }
        }
      }
    } catch (e) {
      debugPrint('Missed check error: $e');
    }
  }
}
