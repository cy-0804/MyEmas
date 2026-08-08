enum DoseStatus {
  scheduled,
  reminderActive,
  taken,
  lateTaken,
  missed,
  skipped,
}

extension DoseStatusExtension on DoseStatus {
  String get name {
    switch (this) {
      case DoseStatus.scheduled:
        return 'scheduled';
      case DoseStatus.reminderActive:
        return 'reminder_active';
      case DoseStatus.taken:
        return 'taken';
      case DoseStatus.lateTaken:
        return 'late_taken';
      case DoseStatus.missed:
        return 'missed';
      case DoseStatus.skipped:
        return 'skipped';
    }
  }

  static DoseStatus fromString(String status) {
    switch (status) {
      case 'scheduled':
        return DoseStatus.scheduled;
      case 'reminder_active':
        return DoseStatus.reminderActive;
      case 'taken':
        return DoseStatus.taken;
      case 'late_taken':
        return DoseStatus.lateTaken;
      case 'missed':
        return DoseStatus.missed;
      case 'skipped':
        return DoseStatus.skipped;
      default:
        return DoseStatus.scheduled;
    }
  }
}
