import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'add_edit_schedule_screen.dart';
import 'medication_dashboard_view.dart';

// ─── STYLE CONSTANTS ──────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF51A77B);
const _kBlue    = Color(0xFF00539E);
const _kBg      = Color(0xFFF6F8FA);
const _kTextDark = Color(0xFF101113);
const _kTextGrey = Color(0xFF6C7278);

// ─── MODELS & METADATA PARSER ───────────────────────────────────────────────
class ScheduleRecord {
  final String id;
  final String elderlyId;
  final String title;
  final DateTime scheduleDateTime;
  final String? location;
  final String? notes; // Raw notes column from database (contains metadata)

  // Decoded metadata fields
  final String scheduleType; // 'Appointment' | 'Medication' | 'Personal'
  final DateTime? endDateTime;
  final bool allDay;
  final DateTime? reminderTime;
  final String? repeatFrequency;
  final String priority; // 'high' | 'medium' | 'low'
  final String? photoUrl;
  final String status; // 'pending' | 'done' | 'skip' | 'missed'
  final String cleanNotes; // User-facing notes (excluding metadata)

  ScheduleRecord({
    required this.id,
    required this.elderlyId,
    required this.title,
    required this.scheduleDateTime,
    this.location,
    this.notes,
    required this.scheduleType,
    this.endDateTime,
    this.allDay = false,
    this.reminderTime,
    this.repeatFrequency,
    required this.priority,
    this.photoUrl,
    required this.status,
    required this.cleanNotes,
  });

  factory ScheduleRecord.fromMap(Map<String, dynamic> m) {
    final rawNotes = m['notes'] as String?;
    final meta = ScheduleMetadata.fromNotes(rawNotes);

    return ScheduleRecord(
      id: m['schedule_id'] as String,
      elderlyId: m['elderly_id'] as String? ?? '',
      title: m['title'] as String? ?? 'Untitled Schedule',
      scheduleDateTime: DateTime.parse(m['schedule_date_time'] as String).toLocal(),
      location: m['location'] as String?,
      notes: rawNotes,
      scheduleType: meta.scheduleType,
      endDateTime: meta.endDateTime,
      allDay: meta.allDay,
      reminderTime: meta.reminderTime,
      repeatFrequency: meta.repeatFrequency,
      priority: meta.priority,
      photoUrl: meta.photoUrl,
      status: meta.status,
      cleanNotes: meta.notesText,
    );
  }
}

class ScheduleMetadata {
  final String scheduleType;
  final DateTime? endDateTime;
  final bool allDay;
  final DateTime? reminderTime;
  final String? repeatFrequency;
  final String priority;
  final String? photoUrl;
  final String status;
  final String notesText;

  ScheduleMetadata({
    required this.scheduleType,
    this.endDateTime,
    this.allDay = false,
    this.reminderTime,
    this.repeatFrequency,
    required this.priority,
    this.photoUrl,
    required this.status,
    required this.notesText,
  });

  factory ScheduleMetadata.fromNotes(String? notes) {
    if (notes == null || notes.isEmpty) {
      return ScheduleMetadata(
        scheduleType: 'Appointment',
        priority: 'medium',
        status: 'pending',
        notesText: '',
      );
    }

    try {
      final marker = '\n\n__METADATA__:';
      final parts = notes.split(marker);
      if (parts.length > 1) {
        final jsonStr = parts.sublist(1).join(marker);
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return ScheduleMetadata(
          scheduleType: map['type'] as String? ?? 'Appointment',
          priority: map['priority'] as String? ?? 'medium',
          status: map['status'] as String? ?? 'pending',
          photoUrl: map['photo_url'] as String?,
          allDay: map['all_day'] as bool? ?? false,
          endDateTime: map['end_date_time'] != null ? DateTime.parse(map['end_date_time']) : null,
          reminderTime: map['reminder_time'] != null ? DateTime.parse(map['reminder_time']) : null,
          repeatFrequency: map['repeat'] as String?,
          notesText: parts[0],
        );
      }
    } catch (_) {}

    return ScheduleMetadata(
      scheduleType: 'Appointment',
      priority: 'medium',
      status: 'pending',
      notesText: notes,
    );
  }

  static String toNotesString({
    required String notesText,
    required String type,
    required String priority,
    required String status,
    required bool allDay,
    DateTime? endDateTime,
    DateTime? reminderTime,
    String? repeat,
    String? photoUrl,
  }) {
    final map = {
      'type': type,
      'priority': priority,
      'status': status,
      'all_day': allDay,
      if (endDateTime != null) 'end_date_time': endDateTime.toIso8601String(),
      if (reminderTime != null) 'reminder_time': reminderTime.toIso8601String(),
      if (repeat != null) 'repeat': repeat,
      if (photoUrl != null) 'photo_url': photoUrl,
    };
    return '$notesText\n\n__METADATA__:${jsonEncode(map)}';
  }
}

// ─── MAIN WIDGET VIEW ────────────────────────────────────────────────────────
class ScheduleDashboardView extends StatefulWidget {
  final String? elderlyId;
  const ScheduleDashboardView({super.key, this.elderlyId});

  @override
  State<ScheduleDashboardView> createState() => _ScheduleDashboardViewState();
}

class _ScheduleDashboardViewState extends State<ScheduleDashboardView> {
  final _db = Supabase.instance.client;

  String _viewMode = 'Day View'; // 'Day View' | 'Week View' | 'Month View'
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';
  String _dateFilter = 'Today'; // 'Today' | 'Tomorrow' | 'Select Date'

  List<ScheduleRecord> _allSchedules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchSchedules();
  }

  Future<void> _fetchSchedules() async {
    setState(() => _loading = true);
    try {
      final uid = widget.elderlyId ?? _db.auth.currentUser?.id;
      if (uid == null) return;

      final res = await _db
          .from('schedule')
          .select()
          .eq('elderly_id', uid)
          .order('schedule_date_time', ascending: true);

      final schedules = (res as List).map((m) => ScheduleRecord.fromMap(m)).toList();
      bool needsRefresh = false;
      
      final now = DateTime.now();
      for (final record in schedules) {
        if (record.repeatFrequency != null && record.repeatFrequency != 'None') {
          // Check if the day has passed
          if (!_isSameDay(record.scheduleDateTime, now) && record.scheduleDateTime.isBefore(now)) {
             DateTime nextDateTime = record.scheduleDateTime;
             while (nextDateTime.isBefore(now) && !_isSameDay(nextDateTime, now)) {
               if (record.repeatFrequency == 'Daily') {
                 nextDateTime = nextDateTime.add(const Duration(days: 1));
               } else if (record.repeatFrequency == 'Weekly') {
                 nextDateTime = nextDateTime.add(const Duration(days: 7));
               } else if (record.repeatFrequency == 'Monthly') {
                 nextDateTime = DateTime(nextDateTime.year, nextDateTime.month + 1, nextDateTime.day, nextDateTime.hour, nextDateTime.minute);
               } else {
                 break;
               }
             }
             
             final newNotes = ScheduleMetadata.toNotesString(
               notesText: record.cleanNotes,
               type: record.scheduleType,
               priority: record.priority,
               status: 'pending',
               allDay: record.allDay,
               endDateTime: record.endDateTime,
               reminderTime: record.reminderTime,
               repeat: record.repeatFrequency,
               photoUrl: record.photoUrl,
             );
             
             await _db.from('schedule').update({
               'schedule_date_time': nextDateTime.toUtc().toIso8601String(),
               'notes': newNotes,
             }).eq('schedule_id', record.id);
             
             needsRefresh = true;
          }
        }
      }

      if (needsRefresh) {
        final res2 = await _db.from('schedule').select().eq('elderly_id', uid).order('schedule_date_time', ascending: true);
        if (mounted) {
          setState(() {
            _allSchedules = (res2 as List).map((m) => ScheduleRecord.fromMap(m)).toList();
            _loading = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _allSchedules = schedules;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Schedule load error: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load Schedule Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _updateStatus(ScheduleRecord record, String newStatus) async {
    try {
      final newNotes = ScheduleMetadata.toNotesString(
        notesText: record.cleanNotes,
        type: record.scheduleType,
        priority: record.priority,
        status: newStatus,
        allDay: record.allDay,
        endDateTime: record.endDateTime,
        reminderTime: record.reminderTime,
        repeat: record.repeatFrequency,
        photoUrl: record.photoUrl,
      );

      await _db.from('schedule').update({
        'notes': newNotes,
      }).eq('schedule_id', record.id);

      _fetchSchedules();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Schedule updated successfully'),
            backgroundColor: _kPrimary,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating schedule status: $e');
    }
  }

  Future<void> _deleteSchedule(String id) async {
    try {
      await _db.from('schedule').delete().eq('schedule_id', id);
      _fetchSchedules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schedule deleted successfully'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint('Error deleting schedule: $e');
    }
  }

  void _navigateToAddEdit({ScheduleRecord? existing}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditScheduleScreen(
          existing: existing,
          elderlyId: widget.elderlyId,
        ),
      ),
    );
    if (result == true) {
      _fetchSchedules();
    }
  }

  // ─── FILTER LOGIC ──────────────────────────────────────────────────────────
  List<ScheduleRecord> get _filteredSchedules {
    return _allSchedules.where((item) {
      // 1. Search Query Filter
      if (_searchQuery.isNotEmpty) {
        final titleMatch = item.title.toLowerCase().contains(_searchQuery.toLowerCase());
        final locMatch = item.location != null &&
            item.location!.toLowerCase().contains(_searchQuery.toLowerCase());
        if (!titleMatch && !locMatch) return false;
      }

      // 2. Date/Calendar Filter based on viewMode
      bool isMatch = false;
      
      if (_viewMode == 'Day View') {
        isMatch = _isSameDay(item.scheduleDateTime, _selectedDate);
      } else if (_viewMode == 'Week View') {
        isMatch = _isSameWeek(item.scheduleDateTime, _selectedDate);
      } else {
        isMatch = _isSameMonth(item.scheduleDateTime, _selectedDate);
      }
      
      // If it doesn't match directly, check if it's a repeating event that falls into the selected period
      if (!isMatch && item.repeatFrequency != null && item.repeatFrequency != 'None') {
        final start = DateTime(item.scheduleDateTime.year, item.scheduleDateTime.month, item.scheduleDateTime.day);
        final target = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        
        // Only show repeating events on or after their start date
        if (!target.isBefore(start)) {
           if (_viewMode == 'Day View') {
             if (item.repeatFrequency == 'Daily') isMatch = true;
             else if (item.repeatFrequency == 'Weekly' && start.weekday == target.weekday) isMatch = true;
             else if (item.repeatFrequency == 'Monthly' && start.day == target.day) isMatch = true;
           } else if (_viewMode == 'Week View') {
             // For week view, Daily and Weekly always appear in subsequent weeks
             if (item.repeatFrequency == 'Daily' || item.repeatFrequency == 'Weekly') isMatch = true;
             else if (item.repeatFrequency == 'Monthly') {
                // Check if the target week contains the monthly day
                final selectedMonday = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
                final startOfWeek = DateTime(selectedMonday.year, selectedMonday.month, selectedMonday.day);
                final endOfWeek = startOfWeek.add(const Duration(days: 6));
                
                // Construct the repeating day in the target month
                final repeatDayThisMonth = DateTime(target.year, target.month, start.day);
                if (!repeatDayThisMonth.isBefore(startOfWeek) && !repeatDayThisMonth.isAfter(endOfWeek)) {
                  isMatch = true;
                } else {
                  // Might be in the overlapping month
                  final repeatDayNextMonth = DateTime(target.year, target.month + 1, start.day);
                  if (!repeatDayNextMonth.isBefore(startOfWeek) && !repeatDayNextMonth.isAfter(endOfWeek)) {
                    isMatch = true;
                  }
                }
             }
           } else {
             // Month View
             if (item.repeatFrequency == 'Daily' || item.repeatFrequency == 'Weekly' || item.repeatFrequency == 'Monthly') {
               isMatch = true;
             }
           }
        }
      }
      
      return isMatch;
    }).toList();
  }

  ScheduleRecord? get _nextEvent {
    final now = DateTime.now();
    final upcoming = _allSchedules.where((item) {
      return item.scheduleDateTime.isAfter(now) && item.status == 'pending';
    }).toList();
    return upcoming.isNotEmpty ? upcoming.first : null;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameWeek(DateTime date, DateTime selected) {
    // Find start of week (Monday)
    final selectedMonday = selected.subtract(Duration(days: selected.weekday - 1));
    final startOfWeek = DateTime(selectedMonday.year, selectedMonday.month, selectedMonday.day);
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    return date.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) &&
        date.isBefore(endOfWeek);
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : RefreshIndicator(
              onRefresh: _fetchSchedules,
              color: _kPrimary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search bar
                    _buildSearchBar(),
                    const SizedBox(height: 18),

                    // Date range status text
                    _buildTodayDateLabel(),
                    const SizedBox(height: 14),

                    // Next Event Section
                    if (_viewMode == 'Day View') ...[
                      _buildSectionHeader('Next Event'),
                      const SizedBox(height: 8),
                      if (_nextEvent != null)
                        _buildNextEventCard(_nextEvent!)
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.event_available, color: _kPrimary),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You have no upcoming events for today.',
                                  style: TextStyle(color: Colors.grey, fontSize: 15, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 18),
                    ],

                    // View Switcher & Filters
                    _buildSectionHeader('Schedule List'),
                    const SizedBox(height: 8),
                    _buildFiltersAndSelectors(),
                    const SizedBox(height: 14),

                    // Search input by title/location
                    _buildSearchInputFilter(),
                    const SizedBox(height: 14),

                    // Calendar UI if Week or Month View
                    if (_viewMode == 'Week View') ...[
                      _buildWeekCalendarSelector(),
                      const SizedBox(height: 14),
                    ] else if (_viewMode == 'Month View') ...[
                      _buildMonthCalendarSelector(),
                      const SizedBox(height: 14),
                    ],

                    // Help instructions
                    Center(
                      child: Text(
                        'Tap card to view details',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Schedule List Items
                    _buildScheduleList(),
                    const SizedBox(height: 20),

                    // Add Button
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: () => _navigateToAddEdit(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text(
                          'Add Schedule',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // ─── WIDGET BUILDERS ────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: 'Search title or location...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildTodayDateLabel() {
    final format = DateFormat('yyyy/M/d, EEEE');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today',
            style: TextStyle(
              fontSize: 16,
              color: _kTextGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            format.format(_selectedDate),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _kTextDark,
              fontFamily: 'League Spartan',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: _kBlue,
        fontFamily: 'League Spartan',
      ),
    );
  }

  Widget _buildNextEventCard(ScheduleRecord event) {
    final timeFormat = DateFormat('h:mm');
    final amPmFormat = DateFormat('a');
    final timeStr = timeFormat.format(event.scheduleDateTime);
    final amPmStr = amPmFormat.format(event.scheduleDateTime);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: IntrinsicHeight(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (event.scheduleType.toLowerCase() == 'medication') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => MedicationDashboardView(elderlyId: event.elderlyId, isStandalone: true)));
            }
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Time Column
            Container(
              width: 80,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.bold,
                      fontSize: 26,
                      color: _kTextDark,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    amPmStr,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            // Vertical Divider
            VerticalDivider(color: Colors.grey.shade300, width: 16, thickness: 1),
            // Details Right Side
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Category & Priority
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          event.scheduleType.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildPriorityTag(event.priority),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Title
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: _kTextDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Location
                  if (event.location != null && event.location!.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.map, size: 14, color: _kBlue),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  // Done / Skip Buttons
                  if (event.scheduleType.toLowerCase() != 'medication')
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _updateStatus(event, 'done'),
                            child: Container(
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _kPrimary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Done',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () => _updateStatus(event, 'skip'),
                            child: Container(
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.red),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Skip',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                ],
              ),
            ),
          ],
        ),
      ), // close GestureDetector
      ), // close IntrinsicHeight
    ); // close Container
  }

  Widget _buildFiltersAndSelectors() {
    return Row(
      children: [
        // Dropdown: Date Filter (Today / Tomorrow / Select Date)
        Expanded(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _dateFilter,
                style: const TextStyle(color: _kTextGrey, fontSize: 13, fontWeight: FontWeight.w600),
                icon: const Icon(Icons.arrow_drop_down, color: _kTextGrey),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _dateFilter = val;
                    if (val == 'Today') {
                      _selectedDate = DateTime.now();
                    } else if (val == 'Tomorrow') {
                      _selectedDate = DateTime.now().add(const Duration(days: 1));
                    } else {
                      _pickCustomDate();
                    }
                  });
                },
                items: ['Today', 'Tomorrow', 'Select Date']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Dropdown: View Mode Selector (Day / Week / Month)
        Expanded(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _viewMode,
                style: const TextStyle(color: _kTextGrey, fontSize: 13, fontWeight: FontWeight.w600),
                icon: const Icon(Icons.arrow_drop_down, color: _kTextGrey),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _viewMode = val;
                  });
                },
                items: ['Day View', 'Week View', 'Month View']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchInputFilter() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _searchQuery.isEmpty ? 'Filter: Title / Location' : 'Searching: $_searchQuery',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.filter_list_alt, color: Colors.grey.shade400, size: 16),
        ],
      ),
    );
  }

  // ─── WEEK CALENDAR SELECTIONS ──────────────────────────────────────────────
  Widget _buildWeekCalendarSelector() {
    final selectedMonday = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
    final weekDays = List.generate(7, (index) => selectedMonday.add(Duration(days: index)));

    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 7,
        itemBuilder: (context, index) {
          final day = weekDays[index];
          final isSelected = _isSameDay(day, _selectedDate);
          final weekdayLabel = DateFormat('E').format(day);
          final dayNum = day.day.toString();

          return GestureDetector(
            onTap: () => setState(() => _selectedDate = day),
            child: Container(
              width: 58,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? _kBlue.withOpacity(0.15) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? _kBlue : Colors.grey.shade200,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekdayLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? _kBlue : _kTextGrey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dayNum,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? _kBlue : _kTextDark,
                    ),
                  ),
                  // Event dot indicator
                  if (_hasEventOnDate(day))
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── MONTH CALENDAR SELECTIONS ─────────────────────────────────────────────
  Widget _buildMonthCalendarSelector() {
    // Basic calendar view grid
    final daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    final firstDayOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final offset = firstDayOfMonth.weekday % 7; // Sun is 0 in some calendars, Mon is 1.

    final gridItems = <Widget>[];

    // Calendar week day headers
    final weekHeaders = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    for (var h in weekHeaders) {
      gridItems.add(
        Center(
          child: Text(
            h,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _kTextGrey),
          ),
        ),
      );
    }

    // Empty offset boxes
    for (var i = 0; i < offset; i++) {
      gridItems.add(const SizedBox());
    }

    // Month days
    for (var dayNum = 1; dayNum <= daysInMonth; dayNum++) {
      final dayDate = DateTime(_selectedDate.year, _selectedDate.month, dayNum);
      final isSelected = _isSameDay(dayDate, _selectedDate);
      final hasEvent = _hasEventOnDate(dayDate);

      gridItems.add(
        GestureDetector(
          onTap: () => setState(() => _selectedDate = dayDate),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected ? _kBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: isSelected ? Border.all(color: _kBlue) : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  dayNum.toString(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : _kTextDark,
                  ),
                ),
                if (hasEvent && !isSelected)
                  Positioned(
                    bottom: 2,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Month Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: _kTextGrey),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
                  });
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(_selectedDate),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kTextDark,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: _kTextGrey),
                onPressed: () {
                  setState(() {
                    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              const Text('Date has event', style: TextStyle(fontSize: 11, color: _kTextGrey)),
            ],
          ),
          const SizedBox(height: 12),
          // Calendar Grid
          GridView.custom(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.1,
            ),
            childrenDelegate: SliverChildListDelegate(gridItems),
          ),
        ],
      ),
    );
  }

  bool _hasEventOnDate(DateTime date) {
    return _allSchedules.any((s) => _isSameDay(s.scheduleDateTime, date));
  }

  void _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
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
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // ─── SCHEDULE LIST BUILDER ──────────────────────────────────────────────────
  Widget _buildScheduleList() {
    final items = _filteredSchedules;

    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.calendar_today_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No schedules found',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildScheduleItemCard(item);
      },
    );
  }

  Widget _buildScheduleItemCard(ScheduleRecord item) {
    final timeFormat = DateFormat('h:mm');
    final amPmFormat = DateFormat('a');
    final timeStr = timeFormat.format(item.scheduleDateTime);
    final amPmStr = amPmFormat.format(item.scheduleDateTime);

    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: InkWell(
          onTap: () {
            if (item.scheduleType.toLowerCase() == 'medication') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => MedicationDashboardView(elderlyId: item.elderlyId, isStandalone: true)));
            } else {
              _showDetailsDialog(item);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Time
                Container(
                  width: 72,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: _kTextDark,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        amPmStr,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Divider
                VerticalDivider(color: Colors.grey.shade200, width: 1, thickness: 1),
                // Details Right Side
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Tags row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.scheduleType.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade600,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            _buildPriorityTag(item.priority),
                            const Spacer(),
                            _buildStatusTag(item.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Title
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: _kTextDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Location
                        if (item.location != null && item.location!.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.map_outlined, size: 12, color: _kBlue),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.location!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
            const Divider(height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (item.scheduleType.toLowerCase() == 'medication') {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => MedicationDashboardView(elderlyId: item.elderlyId, isStandalone: true)));
                        } else {
                          _navigateToAddEdit(existing: item);
                        }
                      },
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: _kBlue,
                      ),
                      label: const Text(
                        'Edit',
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteSchedule(item.id),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: Colors.red,
                      ),
                      label: const Text(
                        'Delete',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
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

  Widget _buildPriorityTag(String priority) {
    Color bg = Colors.grey.shade100;
    Color txt = Colors.grey.shade600;
    String label = 'Priority';

    if (priority == 'high') {
      bg = const Color(0xFFFFB7B5);
      txt = const Color(0xFFF11000);
      label = 'High Priority';
    } else if (priority == 'medium') {
      bg = const Color(0xFFFFC093);
      txt = const Color(0xFF904F00);
      label = 'Medium Priority';
    } else if (priority == 'low') {
      bg = const Color(0xFFFBFFAB);
      txt = const Color(0xFF666E0C);
      label = 'Low Priority';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: txt,
        ),
      ),
    );
  }

  Widget _buildStatusTag(String status) {
    Color color = Colors.grey;
    if (status == 'done') color = _kPrimary;
    if (status == 'skip') color = Colors.red;
    if (status == 'missed') color = Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // ─── DETAILS DIALOG ────────────────────────────────────────────────────────
  void _showDetailsDialog(ScheduleRecord item) {
    showDialog(
      context: context,
      builder: (context) {
        final df = DateFormat('EEEE, d MMMM yyyy, h:mm a');
        final endDf = DateFormat('h:mm a');

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title & Close
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kBlue),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
                const Divider(),
                const SizedBox(height: 10),

                // Schedule Type & Priority
                Row(
                  children: [
                    _buildPriorityTag(item.priority),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.scheduleType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Time Details
                const Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kTextGrey)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time_filled, size: 16, color: _kPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.allDay
                            ? '${DateFormat('EEEE, d MMMM yyyy').format(item.scheduleDateTime)} (All Day)'
                            : '${df.format(item.scheduleDateTime)}${item.endDateTime != null ? ' - ${endDf.format(item.endDateTime!)}' : ''}',
                        style: const TextStyle(fontSize: 14, color: _kTextDark, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Location Details
                if (item.location != null && item.location!.isNotEmpty) ...[
                  const Text('Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kTextGrey)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.location!,
                          style: const TextStyle(fontSize: 14, color: _kTextDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                // Notes
                if (item.cleanNotes.isNotEmpty) ...[
                  const Text('Notes / Comment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kTextGrey)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      item.cleanNotes,
                      style: const TextStyle(fontSize: 13, color: _kTextDark),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Reminder & Repeat
                if (item.reminderTime != null || item.repeatFrequency != null) ...[
                  Row(
                    children: [
                      if (item.reminderTime != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Reminder Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _kTextGrey)),
                              const SizedBox(height: 2),
                              Text(DateFormat('h:mm a').format(item.reminderTime!), style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      if (item.repeatFrequency != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Repeat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _kTextGrey)),
                              const SizedBox(height: 2),
                              Text(item.repeatFrequency!, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                // Photo Display
                if (item.photoUrl != null && item.photoUrl!.isNotEmpty) ...[
                  const Text('Attachment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kTextGrey)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      item.photoUrl!,
                      height: 160,
                      width: double.infinity,
                      fit: double.infinity > 0 ? BoxFit.cover : BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 100,
                          color: Colors.grey.shade100,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Action Bar for Status Updating
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateStatus(item, 'done');
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Mark Done'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateStatus(item, 'skip');
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                      icon: const Icon(Icons.skip_next, size: 16),
                      label: const Text('Skip'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
