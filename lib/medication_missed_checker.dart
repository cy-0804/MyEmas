import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'schedule_dashboard_view.dart';
import 'medication_dashboard_view.dart';

class MedicationMissedChecker {
  static Future<void> checkAndMarkMissed(String elderlyId) async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      // Look back at today (0) and the past 3 days (1..3)
      for (int i = 0; i <= 3; i++) {
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

            final recordStart = DateTime(
              record.scheduleDateTime.year,
              record.scheduleDateTime.month,
              record.scheduleDateTime.day,
            );
            if (targetDate.isBefore(recordStart)) continue;

            if (recordStart == targetDate) {
              isTargetDate = true;
            } else if (record.repeatFrequency == 'Daily') {
              isTargetDate = true;
            } else if (record.repeatFrequency == 'Weekly' &&
                record.scheduleDateTime.weekday == targetDate.weekday) {
              isTargetDate = true;
            } else if (record.repeatFrequency == 'Monthly' &&
                record.scheduleDateTime.day == targetDate.day) {
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

        final meds = (medRes as List)
            .map((m) => Medication.fromMap(m as Map<String, dynamic>))
            .toList();
        if (meds.isEmpty) continue;

        final targetEnd = targetDate.add(const Duration(days: 1));
        final medIds = meds.map((m) => m.id).toList();

        final logRes = await Supabase.instance.client
            .from('medication_logs')
            .select()
            .inFilter('medication_id', medIds)
            .gte('logged_at', targetDate.toUtc().toIso8601String())
            .lt('logged_at', targetEnd.toUtc().toIso8601String());

        final loggedMedIds = (logRes as List)
            .map((l) => l['medication_id'] as String)
            .toSet();

        final todayStr = DateTime(now.year, now.month, now.day);
        for (var med in meds) {
          final isExpired = med.expirationDate != null && med.expirationDate!.isBefore(todayStr);
          if (isExpired) continue;

          if (!loggedMedIds.contains(med.id)) {
            // Check if the session for this medication has passed
            if (_hasSessionPassed(med.whenToTake, targetDate, now)) {
              await Supabase.instance.client.from('medication_logs').insert({
                'medication_id': med.id,
                'logged_at': targetDate
                    .add(const Duration(hours: 23, minutes: 59))
                    .toUtc()
                    .toIso8601String(),
                'status': 'missed',
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Missed check error: $e');
    }
  }

  static bool _hasSessionPassed(String? whenToTake, DateTime targetDate, DateTime now) {
    if (whenToTake == null) return false;

    // If targetDate is strictly before today, it has definitely passed
    if (DateTime(targetDate.year, targetDate.month, targetDate.day)
        .isBefore(DateTime(now.year, now.month, now.day))) {
      return true;
    }

    // Otherwise, check today's session cutoff
    DateTime? cutoff;
    if (whenToTake == 'Morning') {
      cutoff = DateTime(targetDate.year, targetDate.month, targetDate.day, 12, 0); // Morning ends at 12 PM
    } else if (whenToTake == 'Afternoon') {
      cutoff = DateTime(targetDate.year, targetDate.month, targetDate.day, 18, 0); // Afternoon ends at 6 PM
    } else if (whenToTake == 'Evening') {
      cutoff = DateTime(targetDate.year, targetDate.month, targetDate.day, 22, 0); // Evening ends at 10 PM
    } else if (whenToTake == 'Night') {
      cutoff = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59); // Night ends at 11:59 PM
    } else if (whenToTake.contains(':')) {
      // Custom time: session passes 2 hours after the scheduled time
      try {
        final p = whenToTake.split(':');
        int h = int.parse(p[0]);
        int m = int.parse(p[1]);
        cutoff = DateTime(targetDate.year, targetDate.month, targetDate.day, h, m).add(const Duration(hours: 2));
      } catch (_) {}
    }

    if (cutoff != null) {
      return now.isAfter(cutoff);
    }
    return false;
  }
}
