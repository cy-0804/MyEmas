import re

with open('lib/add_edit_schedule_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. State vars
code = code.replace(
    "bool _hasReminder = false;\n  DateTime? _reminderTime;",
    "bool _hasReminder = false;\n  String _reminderPreset = '30 mins before';\n  DateTime? _reminderTime;"
)

# 2. initState
code = code.replace(
"""      _hasReminder = item.reminderTime != null;
      _reminderTime = item.reminderTime;
      _repeatFrequency = item.repeatFrequency ?? 'None';""",
"""      _hasReminder = item.reminderTime != null;
      _reminderTime = item.reminderTime;
      if (_hasReminder && _reminderTime != null) {
        final diff = _startDateTime.difference(_reminderTime!);
        if (diff.inMinutes == 10) {
          _reminderPreset = '10 mins before';
        } else if (diff.inMinutes == 30) {
          _reminderPreset = '30 mins before';
        } else if (diff.inMinutes == 60) {
          _reminderPreset = '1 hour before';
        } else if (diff.inHours == 24) {
          _reminderPreset = '1 day before';
        } else {
          _reminderPreset = 'Custom';
        }
      }
      _repeatFrequency = item.repeatFrequency ?? 'None';"""
)

# 3. _save
code = code.replace(
"""      // Pack additional form properties into notes metadata
      final finalNotes = ScheduleMetadata.toNotesString(
        notesText: _notesCtrl.text.trim(),
        type: _scheduleType,
        priority: _priority,
        status: widget.existing?.status ?? 'pending',
        allDay: _allDay,
        endDateTime: _endDateTime,
        reminderTime: _hasReminder ? _reminderTime : null,
        repeat: _repeatFrequency != 'None' ? _repeatFrequency : null,""",
"""      DateTime? finalReminderTime;
      if (_hasReminder) {
        if (_reminderPreset == '10 mins before') {
          finalReminderTime = _startDateTime.subtract(const Duration(minutes: 10));
        } else if (_reminderPreset == '30 mins before') {
          finalReminderTime = _startDateTime.subtract(const Duration(minutes: 30));
        } else if (_reminderPreset == '1 hour before') {
          finalReminderTime = _startDateTime.subtract(const Duration(hours: 1));
        } else if (_reminderPreset == '1 day before') {
          finalReminderTime = _startDateTime.subtract(const Duration(days: 1));
        } else {
          finalReminderTime = _reminderTime;
        }
      }

      // Pack additional form properties into notes metadata
      final finalNotes = ScheduleMetadata.toNotesString(
        notesText: _notesCtrl.text.trim(),
        type: _scheduleType,
        priority: _priority,
        status: widget.existing?.status ?? 'pending',
        allDay: _allDay,
        endDateTime: _endDateTime,
        reminderTime: finalReminderTime,
        repeat: _repeatFrequency != 'None' ? _repeatFrequency : null,"""
)

# 4. build Reminder Switch
target_build = """                    if (_hasReminder) ...[
                      SizedBox(height: 6),
                      InkWell(
                        onTap: _pickReminderTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.alarm, color: _kBlue, size: 20),
                              SizedBox(width: 10),
                              Text(
                                _reminderTime != null
                                    ? DateFormat(
                                        'h:mm a',
                                      ).format(_reminderTime!)
                                    : 'Tap to select reminder time',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _reminderTime != null
                                      ? _kTextDark
                                      : Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],"""

replace_build = """                    if (_hasReminder) ...[
                      SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _reminderPreset,
                            isExpanded: true,
                            style: const TextStyle(
                              color: _kTextDark,
                              fontSize: 14,
                            ),
                            onChanged: (val) {
                              setState(() {
                                _reminderPreset = val!;
                                if (val != 'Custom' && _reminderTime == null) {
                                  _reminderTime = DateTime.now(); // fallback
                                }
                              });
                            },
                            items: [
                              '10 mins before',
                              '30 mins before',
                              '1 hour before',
                              '1 day before',
                              'Custom'
                            ]
                                .map((s) => DropdownMenuItem(value: s, child: Text(s.tr())))
                                .toList(),
                          ),
                        ),
                      ),
                      if (_reminderPreset == 'Custom') ...[
                        SizedBox(height: 10),
                        InkWell(
                          onTap: _pickReminderTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.alarm, color: _kBlue, size: 20),
                                SizedBox(width: 10),
                                Text(
                                  _reminderTime != null
                                      ? DateFormat('MMM d, h:mm a').format(_reminderTime!)
                                      : 'Tap to select custom reminder time'.tr(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _reminderTime != null
                                        ? _kTextDark
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],"""

code = code.replace(target_build, replace_build)

with open('lib/add_edit_schedule_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Done")
