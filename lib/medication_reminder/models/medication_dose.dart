import 'dose_status.dart';

class MedicationDose {
  final String id; // Unique ID for this dose (e.g., medId_timestamp)
  final String medicationId;
  final String name;
  final String? dosage;
  final String? instruction;
  final String? photo;
  final DateTime scheduledTime;
  final DateTime windowEnd;
  DateTime? actualTakenTime;
  DoseStatus status;
  int reminderCount;
  int snoozeCount;
  final int minIntervalHours;

  MedicationDose({
    required this.id,
    required this.medicationId,
    required this.name,
    this.dosage,
    this.instruction,
    this.photo,
    required this.scheduledTime,
    required this.windowEnd,
    this.actualTakenTime,
    this.status = DoseStatus.scheduled,
    this.reminderCount = 0,
    this.snoozeCount = 0,
    this.minIntervalHours = 4,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medication_id': medicationId,
      'name': name,
      'dosage': dosage,
      'instruction': instruction,
      'photo': photo,
      'scheduled_time': scheduledTime.toIso8601String(),
      'window_end': windowEnd.toIso8601String(),
      'actual_taken_time': actualTakenTime?.toIso8601String(),
      'status': status.name,
      'reminder_count': reminderCount,
      'snooze_count': snoozeCount,
      'min_interval_hours': minIntervalHours,
    };
  }

  factory MedicationDose.fromMap(Map<String, dynamic> map) {
    return MedicationDose(
      id: map['id'],
      medicationId: map['medication_id'],
      name: map['name'],
      dosage: map['dosage'],
      instruction: map['instruction'],
      photo: map['photo'],
      scheduledTime: DateTime.parse(map['scheduled_time']),
      windowEnd: DateTime.parse(map['window_end']),
      actualTakenTime: map['actual_taken_time'] != null
          ? DateTime.parse(map['actual_taken_time'])
          : null,
      status: DoseStatusExtension.fromString(map['status']),
      reminderCount: map['reminder_count'] ?? 0,
      snoozeCount: map['snooze_count'] ?? 0,
      minIntervalHours: map['min_interval_hours'] ?? 4,
    );
  }
}
