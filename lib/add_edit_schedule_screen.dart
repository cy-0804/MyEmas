import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'schedule_dashboard_view.dart';
import 'package:easy_localization/easy_localization.dart';
import 'location_search_field.dart';

const _kPrimary = Color(0xFF51A77B);
const _kBlue = Color(0xFF00539E);
const _kBg = Color(0xFFF6F8FA);
const _kTextDark = Color(0xFF101113);
const _kTextGrey = Color(0xFF6C7278);

class AddEditScheduleScreen extends StatefulWidget {
  final ScheduleRecord? existing;
  final String? elderlyId;

  const AddEditScheduleScreen({super.key, this.existing, this.elderlyId});

  @override
  State<AddEditScheduleScreen> createState() => _AddEditScheduleScreenState();
}

class _AddEditScheduleScreenState extends State<AddEditScheduleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = Supabase.instance.client;

  late TextEditingController _titleCtrl;
  late TextEditingController _locationCtrl;
  late TextEditingController _notesCtrl;

  String _scheduleType =
      'Appointment'; // 'Appointment' | 'Medication' | 'Personal'
  DateTime _startDateTime = DateTime.now().add(const Duration(hours: 1));
  DateTime? _endDateTime;
  bool _allDay = false;

  bool _hasReminder = false;
  String _reminderPreset = '30 mins before';
  DateTime? _reminderTime;

  String? _repeatFrequency = 'None'; // 'None' | 'Daily' | 'Weekly' | 'Monthly'

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;

    _titleCtrl = TextEditingController(text: item?.title ?? '');
    _locationCtrl = TextEditingController(text: item?.location ?? '');
    _notesCtrl = TextEditingController(text: item?.cleanNotes ?? '');

    if (item != null) {
      _scheduleType = item.scheduleType;
      _startDateTime = item.scheduleDateTime;
      _endDateTime = item.endDateTime;
      _allDay = item.allDay;
      _hasReminder = item.reminderTime != null;
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
      _repeatFrequency = item.repeatFrequency ?? 'None';
    } else {
      _endDateTime = _startDateTime.add(const Duration(hours: 1));
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initialDate = isStart
        ? _startDateTime
        : (_endDateTime ?? _startDateTime);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _kPrimary,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date == null) return;

    if (!mounted) return;
    final initialTime = TimeOfDay.fromDateTime(initialDate);
    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (time == null) return;

    final finalDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart) {
        _startDateTime = finalDateTime;
        if (_endDateTime != null && _endDateTime!.isBefore(_startDateTime)) {
          _endDateTime = _startDateTime.add(const Duration(hours: 1));
        }
      } else {
        _endDateTime = finalDateTime;
      }
    });
  }

  Future<void> _pickReminderTime() async {
    final initialTime = _reminderTime != null
        ? TimeOfDay.fromDateTime(_reminderTime!)
        : const TimeOfDay(hour: 9, minute: 0);
    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (time == null) return;

    setState(() {
      final now = DateTime.now();
      _reminderTime = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final uid = widget.elderlyId ?? _db.auth.currentUser?.id;
      if (uid == null) throw Exception('Not logged in');

      // Ensure the user exists in the elderly table (e.g. if they clicked 'Skip for now' on onboarding)
      final elderlyRes = await _db
          .from('elderly')
          .select('user_id')
          .eq('user_id', uid)
          .limit(1)
          .maybeSingle();

      if (elderlyRes == null) {
        await _db.from('elderly').insert({'user_id': uid});
      }

      DateTime? finalReminderTime;
      if (_hasReminder) {
        if (_reminderPreset == '10 mins before') {
          finalReminderTime = _startDateTime.subtract(
            const Duration(minutes: 10),
          );
        } else if (_reminderPreset == '30 mins before') {
          finalReminderTime = _startDateTime.subtract(
            const Duration(minutes: 30),
          );
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
        priority: 'medium',
        status: widget.existing?.status ?? 'pending',
        allDay: _allDay,
        endDateTime: _endDateTime,
        reminderTime: finalReminderTime,
        repeat: _repeatFrequency != 'None' ? _repeatFrequency : null,
        photoUrl: null,
      );

      final row = {
        'elderly_id': uid,
        'title': _titleCtrl.text.trim(),
        'schedule_date_time': _startDateTime.toUtc().toIso8601String(),
        'location': _locationCtrl.text.trim(),
        'notes': finalNotes,
      };

      if (widget.existing != null) {
        await _db
            .from('schedule')
            .update(row)
            .eq('schedule_id', widget.existing!.id);
      } else {
        await _db.from('schedule').insert(row);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy/MM/dd, h:mm a');

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.existing != null ? 'Edit Schedule' : 'Add Schedule',
          style: const TextStyle(
            color: _kTextDark,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _saving
          ? Center(child: CircularProgressIndicator(color: _kPrimary))
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title Input
                      _buildLabel('Title', required: true),
                      SizedBox(height: 6),
                      TextFormField(
                        controller: _titleCtrl,
                        style: const TextStyle(color: _kTextDark, fontSize: 15),
                        decoration: _inputDecoration('Enter schedule title...'),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Title is required'
                            : null,
                      ),
                      SizedBox(height: 16),

                      // Schedule Type Buttons
                      _buildLabel('Schedule Type', required: true),
                      SizedBox(height: 6),
                      _buildScheduleTypeSelector(),
                      SizedBox(height: 16),

                      // Location Input
                      _buildLabel('Location', required: true),
                      SizedBox(height: 6),
                      LocationSearchField(
                        controller: _locationCtrl,
                        label: 'Location',
                        hint: 'Enter location...',
                        prefixIcon: Icons.location_on_outlined,
                        themeColor: _kBlue,
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Location is required'
                            : null,
                      ),
                      SizedBox(height: 16),

                      // Date & Time Picker Cards
                      Row(
                        children: [
                          _buildLabel('Date & Time', required: true),
                          const Spacer(),
                          Text(
                            'All Day'.tr(),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _kTextDark,
                            ),
                          ),
                          SizedBox(width: 4),
                          Switch(
                            value: _allDay,
                            activeThumbColor: _kBlue,
                            onChanged: (val) => setState(() => _allDay = val),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      _buildDateTimePickerCard(
                        label: 'Start Date & Time'.tr(),
                        dateTime: _startDateTime,
                        onTap: () => _pickDateTime(isStart: true),
                        df: df,
                      ),
                      if (!_allDay) ...[
                        SizedBox(height: 10),
                        _buildDateTimePickerCard(
                          label: 'End Date & Time'.tr(),
                          dateTime: _endDateTime,
                          onTap: () => _pickDateTime(isStart: false),
                          df: df,
                        ),
                      ],
                      SizedBox(height: 16),

                      // Reminder Picker
                      Row(
                        children: [
                          _buildLabel('Reminder', required: false),
                          const Spacer(),
                          Switch(
                            value: _hasReminder,
                            activeThumbColor: _kBlue,
                            onChanged: (val) =>
                                setState(() => _hasReminder = val),
                          ),
                        ],
                      ),
                      if (_hasReminder) ...[
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
                                  if (val != 'Custom' &&
                                      _reminderTime == null) {
                                    _reminderTime = DateTime.now(); // fallback
                                  }
                                });
                              },
                              items:
                                  [
                                        '10 mins before',
                                        '30 mins before',
                                        '1 hour before',
                                        '1 day before',
                                        'Custom',
                                      ]
                                      .map(
                                        (s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(s.tr()),
                                        ),
                                      )
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
                                  const Icon(
                                    Icons.alarm,
                                    color: _kBlue,
                                    size: 20,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    _reminderTime != null
                                        ? DateFormat(
                                            'MMM d, h:mm a',
                                          ).format(_reminderTime!)
                                        : 'Tap to select custom reminder time'
                                              .tr(),
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
                      ],
                      SizedBox(height: 16),

                      // Repeat Frequency Selection
                      _buildLabel('Repeat', required: false),
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
                            value: _repeatFrequency,
                            isExpanded: true,
                            style: const TextStyle(
                              color: _kTextDark,
                              fontSize: 14,
                            ),
                            onChanged: (val) =>
                                setState(() => _repeatFrequency = val),
                            items: ['None', 'Daily', 'Weekly', 'Monthly']
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),

                      // Notes / Comment Input
                      _buildLabel('Notes / Comment', required: false),
                      SizedBox(height: 6),
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 4,
                        style: const TextStyle(color: _kTextDark, fontSize: 14),
                        decoration: _inputDecoration(
                          'Enter any notes or special comments here...',
                        ),
                      ),
                      SizedBox(height: 16),

                      // Save Button
                      Center(
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 1,
                            ),
                            child: Text(
                              'Save Schedule'.tr(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ─── COMPONENT BUILDERS ───────────────────────────────────────────────────

  Widget _buildLabel(String text, {bool required = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: _kTextDark,
            fontFamily: 'Inter',
          ),
        ),
        if (required) ...[
          SizedBox(width: 2),
          Text(
            '*',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
        ],
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kPrimary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }

  Widget _buildScheduleTypeSelector() {
    final types = ['Appointment', 'Personal'];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: types.map((type) {
          final isSelected = _scheduleType == type;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _scheduleType = type),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? _kBlue.withOpacity(0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  type,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isSelected ? _kBlue : _kTextDark,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateTimePickerCard({
    required String label,
    required DateTime? dateTime,
    required VoidCallback onTap,
    required DateFormat df,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              color: _kPrimary,
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    dateTime != null ? df.format(dateTime) : 'Tap to select',
                    style: const TextStyle(
                      fontSize: 14,
                      color: _kTextDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
